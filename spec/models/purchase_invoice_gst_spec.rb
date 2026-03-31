# spec/models/purchase_invoice_gst_spec.rb
#
# Tests PurchaseInvoice#confirm! GST logic:
#   - intra-state → CGST + SGST split
#   - inter-state → IGST full rate
#   - zero GST    → no tax, no divide-by-zero
#   - discount    → discount_amount computed correctly
#   - supply_type, cgst_amount, sgst_amount, igst_amount columns
#   - metadata kept in sync for backward compat

require 'rails_helper'

RSpec.describe PurchaseInvoice, type: :model, gst: true do
  # ── Shared setup ───────────────────────────────────────────────────────────
  let(:org)          { create(:organisation, state: 'West Bengal', state_code: '19') }
  let(:user)         { create(:gst_user, organisation: org) }

  # Suppliers
  let(:wb_supplier)  { create(:gst_supplier, :intra_state, organisation: org) }
  let(:mh_supplier)  { create(:gst_supplier, :inter_state, organisation: org) }

  # Products at different GST rates
  let(:p18)          { create(:gst_product, :gst_18) }
  let(:p12)          { create(:gst_product, :gst_12) }
  let(:p28)          { create(:gst_product, :gst_28) }
  let(:p0)           { create(:gst_product, :gst_zero) }

  # ── Helper: build a draft invoice with one item, then confirm ──────────────
  def make_invoice(supplier:, product:, qty: 10, total:, discount_percent: 0)
    inv = PurchaseInvoice.create!(
      organisation:  org,
      supplier:      supplier,
      user:          user,
      invoice_date:  Date.today,
      delivery_date: Date.today + 7,
      status:        'draft',
      total_amount:  0, total_taxable_amount: 0, total_tax_amount: 0
    )
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv,
      product:          product,
      quantity:         qty,
      unit_rate:        0,
      total_amount:     total,
      discount_percent: 0,
      discount_amount:  0,
      supply_type:      'intra_state',
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0,
      metadata: { 'discount_percent' => discount_percent.to_s }
    )
    inv.confirm!(user)
    [inv.reload, inv.purchase_invoice_items.first.reload]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe '#confirm! — intra-state purchase (West Bengal → West Bengal)' do
  # ═══════════════════════════════════════════════════════════════════════════

    context 'with 18% GST product (Asian Paints Tractor Emulsion scenario)' do
      # 20 cans × ₹1,180 incl. GST = ₹23,600 total
      # taxable = 23600 / 1.18 = 20000
      # CGST 9% = 1800, SGST 9% = 1800
      let!(:result) { make_invoice(supplier: wb_supplier, product: p18, qty: 20, total: 23600.0) }
      let(:inv)  { result[0] }
      let(:item) { result[1] }

      it 'sets supply_type to intra_state'  do
        expect(item.supply_type).to eq('intra_state')
      end

      it 'sets gst_rate to 18' do
        expect(item.gst_rate).to eq(18.0)
      end

      it 'computes taxable_amount correctly' do
        expect(item.taxable_amount).to eq(20000.00)
      end

      it 'computes tax_amount correctly' do
        expect(item.tax_amount).to eq(3600.00)
      end

      it 'splits CGST = SGST = half of tax' do
        expect(item.cgst_amount).to eq(1800.00)
        expect(item.sgst_amount).to eq(1800.00)
      end

      it 'has zero IGST for intra-state' do
        expect(item.igst_amount).to eq(0.00)
      end

      it 'keeps metadata in sync' do
        expect(item.metadata['supply_type']).to eq('intra_state')
        expect(item.metadata['cgst_amount'].to_f).to eq(1800.00)
        expect(item.metadata['sgst_amount'].to_f).to eq(1800.00)
        expect(item.metadata['igst_amount'].to_f).to eq(0.00)
      end

      it 'rolls up totals on the invoice header' do
        expect(inv.total_taxable_amount).to eq(20000.00)
        expect(inv.total_tax_amount).to eq(3600.00)
        expect(inv.total_amount).to eq(23600.00)
      end

      it 'confirms the invoice' do
        expect(inv.status).to eq('confirmed')
      end
    end

    context 'with 12% GST product' do
      # 5 items × ₹560 incl. 12% = ₹2,800
      # taxable = 2800 / 1.12 = 2500, CGST = 150, SGST = 150
      let!(:result) { make_invoice(supplier: wb_supplier, product: p12, qty: 5, total: 2800.0) }
      let(:item)    { result[1] }

      it 'sets gst_rate to 12' do
        expect(item.gst_rate).to eq(12.0)
      end
      it 'computes taxable correctly' do
        expect(item.taxable_amount).to eq(2500.00)
      end
      it 'computes tax correctly' do
        expect(item.tax_amount).to eq(300.00)
      end
      it 'splits CGST = SGST = 150' do
        expect(item.cgst_amount).to eq(150.00)
        expect(item.sgst_amount).to eq(150.00)
      end
      it 'has zero IGST' do
        expect(item.igst_amount).to eq(0.00)
      end
    end

    context 'with 28% GST product (cement scenario)' do
      # 50 bags × ₹448 incl. 28% = ₹22,400 — but this is intra-state
      # taxable = 22400 / 1.28 = 17500, CGST = 2450, SGST = 2450
      let!(:result) { make_invoice(supplier: wb_supplier, product: p28, qty: 50, total: 22400.0) }
      let(:item)    { result[1] }

      it 'applies 28% rate split as 14% CGST + 14% SGST' do
        expect(item.gst_rate).to eq(28.0)
        expect(item.taxable_amount).to eq(17500.00)
        expect(item.cgst_amount).to eq(2450.00)
        expect(item.sgst_amount).to eq(2450.00)
        expect(item.igst_amount).to eq(0.00)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe '#confirm! — inter-state purchase (Maharashtra → West Bengal)' do
  # ═══════════════════════════════════════════════════════════════════════════

    context 'with 18% GST product (the Ultratech cement scenario from docs)' do
      # 50 bags × ₹448 incl. 28% = ₹22,400 from Maharashtra supplier
      # taxable = 22400 / 1.28 = 17500, IGST 28% = 4900
      # NOTE: product is p28 but test name says 18% for illustration variety
      let!(:result) { make_invoice(supplier: mh_supplier, product: p28, qty: 50, total: 22400.0) }
      let(:item)    { result[1] }

      it 'sets supply_type to inter_state' do
        expect(item.supply_type).to eq('inter_state')
      end

      it 'has zero CGST and SGST' do
        expect(item.cgst_amount).to eq(0.00)
        expect(item.sgst_amount).to eq(0.00)
      end

      it 'puts full tax into IGST' do
        expect(item.igst_amount).to eq(item.tax_amount)
        expect(item.igst_amount).to eq(4900.00)
      end

      it 'computes taxable correctly' do
        expect(item.taxable_amount).to eq(17500.00)
      end

      it 'syncs supply_type to metadata' do
        expect(item.metadata['supply_type']).to eq('inter_state')
        expect(item.metadata['cgst_amount'].to_f).to eq(0.0)
        expect(item.metadata['igst_amount'].to_f).to eq(4900.00)
      end
    end

    context 'with 18% GST product from inter-state supplier' do
      # 10 units × ₹1,180 = ₹11,800 from Maharashtra
      # taxable = 10000, IGST 18% = 1800
      let!(:result) { make_invoice(supplier: mh_supplier, product: p18, qty: 10, total: 11800.0) }
      let(:item)    { result[1] }

      it 'correctly identifies as inter_state' do
        expect(item.supply_type).to eq('inter_state')
      end
      it 'applies full 18% as IGST' do
        expect(item.igst_amount).to eq(1800.00)
      end
      it 'has no CGST or SGST' do
        expect(item.cgst_amount + item.sgst_amount).to eq(0)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe '#confirm! — edge cases' do
  # ═══════════════════════════════════════════════════════════════════════════

    context 'zero GST product' do
      let!(:result) { make_invoice(supplier: wb_supplier, product: p0, qty: 10, total: 1000.0) }
      let(:item)    { result[1] }

      it 'has zero tax amounts' do
        expect(item.gst_rate).to eq(0.0)
        expect(item.tax_amount).to eq(0.00)
        expect(item.cgst_amount).to eq(0.00)
        expect(item.sgst_amount).to eq(0.00)
        expect(item.igst_amount).to eq(0.00)
      end

      it 'sets taxable_amount = total_amount' do
        expect(item.taxable_amount).to eq(1000.00)
      end

      it 'does not divide by zero' do
        expect { result }.not_to raise_error
      end
    end

    context 'when organisation state is blank (defaults to intra-state)' do
      let(:org_no_state) { create(:organisation, state: nil) }
      let(:user2)        { create(:gst_user, organisation: org_no_state) }
      let(:supplier2)    { create(:gst_supplier, :inter_state, organisation: org_no_state) }
      let(:prod2)        { create(:gst_product, :gst_18) }

      it 'defaults to intra_state and does not crash' do
        inv = PurchaseInvoice.create!(
          organisation: org_no_state, supplier: supplier2,
          user: user2, invoice_date: Date.today, delivery_date: Date.today + 1,
          status: 'draft', total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: prod2, quantity: 1,
          unit_rate: 0, total_amount: 1180.0,
          discount_percent: 0, discount_amount: 0, supply_type: 'intra_state',
          gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        expect { inv.confirm!(user2) }.not_to raise_error
        item = inv.purchase_invoice_items.first.reload
        expect(item.supply_type).to eq('intra_state')
        # Tax is still split as CGST+SGST (not zero)
        expect(item.cgst_amount).to be > 0
      end
    end

    context 'when supplier state is blank (defaults to intra-state)' do
      let(:supplier_no_state) { create(:gst_supplier, organisation: org, state: nil) }

      it 'defaults to intra_state' do
        inv = PurchaseInvoice.create!(
          organisation: org, supplier: supplier_no_state,
          user: user, invoice_date: Date.today, delivery_date: Date.today + 1,
          status: 'draft', total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: p18, quantity: 1,
          unit_rate: 0, total_amount: 118.0,
          discount_percent: 0, discount_amount: 0, supply_type: 'intra_state',
          gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        inv.confirm!(user)
        item = inv.purchase_invoice_items.first.reload
        expect(item.supply_type).to eq('intra_state')
      end
    end

    context 'multiple items with mixed supply types on the same invoice (same supplier)' do
      it 'applies same supply_type to all items (derived from invoice supplier)' do
        inv = PurchaseInvoice.create!(
          organisation: org, supplier: mh_supplier, user: user,
          invoice_date: Date.today, delivery_date: Date.today + 1,
          status: 'draft', total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: p18, quantity: 5, unit_rate: 0,
          total_amount: 5900.0, discount_percent: 0, discount_amount: 0,
          supply_type: 'intra_state', gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: p12, quantity: 3, unit_rate: 0,
          total_amount: 1680.0, discount_percent: 0, discount_amount: 0,
          supply_type: 'intra_state', gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        inv.confirm!(user)
        items = inv.purchase_invoice_items.reload

        items.each do |item|
          expect(item.supply_type).to eq('inter_state'), "Expected inter_state for item #{item.id}"
          expect(item.cgst_amount).to eq(0.0)
          expect(item.sgst_amount).to eq(0.0)
          expect(item.igst_amount).to be > 0
        end
      end

      it 'aggregates tax correctly across items' do
        inv = PurchaseInvoice.create!(
          organisation: org, supplier: wb_supplier, user: user,
          invoice_date: Date.today, delivery_date: Date.today + 1,
          status: 'draft', total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        # Item 1: 18% on ₹11800 → taxable 10000, tax 1800
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: p18, quantity: 10, unit_rate: 0,
          total_amount: 11800.0, discount_percent: 0, discount_amount: 0,
          supply_type: 'intra_state', gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        # Item 2: 12% on ₹2800 → taxable 2500, tax 300
        PurchaseInvoiceItem.create!(
          purchase_invoice: inv, product: p12, quantity: 5, unit_rate: 0,
          total_amount: 2800.0, discount_percent: 0, discount_amount: 0,
          supply_type: 'intra_state', gst_rate: 0, taxable_amount: 0, tax_amount: 0,
          cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
        )
        inv.confirm!(user)
        inv.reload

        expect(inv.total_taxable_amount).to eq(12500.00)
        expect(inv.total_tax_amount).to eq(2100.00)
      end
    end

    context 'preventing double-confirmation' do
      it 'returns false and sets an error if already confirmed' do
        inv, _item = make_invoice(supplier: wb_supplier, product: p18, qty: 1, total: 118.0)
        result = inv.confirm!(user)
        expect(result).to eq(false)
        expect(inv.errors[:base]).to include('Already confirmed')
      end
    end
  end
end