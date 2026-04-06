# spec/models/sales_invoice_gst_spec.rb
#
# Tests SalesInvoiceItem#compute_amounts GST logic:
#   - intra-state → CGST + SGST from metadata percents
#   - inter-state → IGST full rate
#   - walk-in (no customer) → intra-state default
#   - zero GST, discount, multiple items

require 'rails_helper'

RSpec.describe SalesInvoiceItem, type: :model, gst: true do

  let(:org)         { create(:organisation, state: 'West Bengal', state_code: '19') }
  let(:user)        { create(:gst_user, organisation: org) }
  let(:wb_customer) { create(:gst_customer, :intra_state, organisation: org) }
  let(:bi_customer) { create(:gst_customer, :inter_state, organisation: org) }  # Bihar
  let(:b2b_cust)    { create(:gst_customer, :intra_state, :b2b, organisation: org) }

  let(:p18)         { create(:gst_product, :gst_18) }
  let(:p12)         { create(:gst_product, :gst_12) }
  let(:p0)          { create(:gst_product, :gst_zero) }

  def build_item(invoice, product:, qty: 5, total:, cgst_pct: 9.0, sgst_pct: 9.0, discount: 0)
    SalesInvoiceItem.create!(
      sales_invoice:   invoice,
      product:         product,
      line_type:       'product',
      quantity:        qty,
      total_amount:    total,
      discount_percent: discount,
      metadata:        { 'cgst_percent' => cgst_pct, 'sgst_percent' => sgst_pct }
    )
  end

  def draft_invoice(customer)
    SalesInvoice.create!(
      organisation: org, customer: customer, user: user,
      invoice_date: Date.today, status: 'draft',
      total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe 'compute_amounts — intra-state sale (West Bengal → West Bengal)' do
  # ═══════════════════════════════════════════════════════════════════════════

    let(:invoice) { draft_invoice(wb_customer) }

    context 'standard 18% product (3 cans × ₹1350 = ₹4050)' do
      subject(:item) { build_item(invoice, product: p18, qty: 3, total: 4050.0) }

      it 'sets supply_type to intra_state' do
        expect(item.supply_type).to eq('intra_state')
      end

      it 'computes gst_rate as 18' do
        expect(item.gst_rate).to eq(18.0)
      end

      it 'computes taxable_amount correctly' do
        # 4050 / 1.18 = 3432.20
        expect(item.taxable_amount).to eq(3432.20)
      end

      it 'computes tax_amount correctly' do
        # 4050 - 3432.20 = 617.80
        expect(item.tax_amount).to eq(617.80)
      end

      it 'splits tax as CGST + SGST (equal)' do
        expect(item.cgst_amount).to be_within(0.01).of(308.90)
        expect(item.sgst_amount).to be_within(0.01).of(308.90)
        expect(item.cgst_amount).to eq(item.sgst_amount)
      end

      it 'has zero IGST' do
        expect(item.igst_amount).to eq(0.0)
      end

      it 'keeps metadata in sync' do
        expect(item.metadata['cgst_amount'].to_f).to be_within(0.01).of(308.90)
        expect(item.metadata['sgst_amount'].to_f).to be_within(0.01).of(308.90)
        expect(item.metadata['igst_amount'].to_f).to eq(0.0)
      end
    end

    context '12% GST product' do
      # 10 units × ₹112 = ₹1120, taxable = 1000, CGST = 60, SGST = 60
      subject(:item) { build_item(invoice, product: p12, qty: 10, total: 1120.0, cgst_pct: 6.0, sgst_pct: 6.0) }

      it 'uses 12% rate' do
        expect(item.gst_rate).to eq(12.0)
      end
      it 'calculates taxable' do
        expect(item.taxable_amount).to eq(1000.00)
      end
      it 'calculates CGST 6%' do
        expect(item.cgst_amount).to eq(60.00)
      end
      it 'calculates SGST 6%' do
        expect(item.sgst_amount).to eq(60.00)
      end
      it 'has zero IGST' do
        expect(item.igst_amount).to eq(0.0)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe 'compute_amounts — inter-state sale (West Bengal → Bihar)' do
  # ═══════════════════════════════════════════════════════════════════════════

    let(:invoice) { draft_invoice(bi_customer) }

    context 'standard 18% product sold to Bihar customer' do
      # 5 units × ₹1180 = ₹5900
      # taxable = 5000, IGST 18% = 900
      subject(:item) { build_item(invoice, product: p18, qty: 5, total: 5900.0) }

      it 'detects inter_state from customer state mismatch' do
        expect(item.supply_type).to eq('inter_state')
      end

      it 'has zero CGST' do
        expect(item.cgst_amount).to eq(0.0)
      end

      it 'has zero SGST' do
        expect(item.sgst_amount).to eq(0.0)
      end

      it 'puts full 18% tax into IGST' do
        expect(item.igst_amount).to eq(item.tax_amount)
        expect(item.igst_amount).to eq(900.00)
      end

      it 'updates cgst_percent and sgst_percent to 0 in metadata' do
        expect(item.metadata['cgst_percent'].to_f).to eq(0.0)
        expect(item.metadata['sgst_percent'].to_f).to eq(0.0)
        expect(item.metadata['igst_percent'].to_f).to eq(18.0)
      end

      it 'sets igst_amount in metadata' do
        expect(item.metadata['igst_amount'].to_f).to eq(900.00)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe 'compute_amounts — walk-in / no customer' do
  # ═══════════════════════════════════════════════════════════════════════════

    let(:invoice) do
      SalesInvoice.create!(
        organisation: org, customer: nil, user: user,
        invoice_date: Date.today, status: 'draft',
        total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
      )
    end

    subject(:item) { build_item(invoice, product: p18, qty: 2, total: 2360.0) }

    it 'defaults to intra_state when no customer' do
      expect(item.supply_type).to eq('intra_state')
    end

    it 'splits as CGST + SGST' do
      expect(item.cgst_amount).to be > 0
      expect(item.sgst_amount).to be > 0
      expect(item.igst_amount).to eq(0.0)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  describe 'compute_amounts — edge cases' do
  # ═══════════════════════════════════════════════════════════════════════════

    let(:invoice) { draft_invoice(wb_customer) }

    context 'zero GST product' do
      subject(:item) { build_item(invoice, product: p0, qty: 5, total: 500.0, cgst_pct: 0.0, sgst_pct: 0.0) }

      it 'has zero tax amounts' do
        expect(item.tax_amount).to eq(0.0)
        expect(item.cgst_amount).to eq(0.0)
        expect(item.igst_amount).to eq(0.0)
      end

      it 'sets taxable_amount = total_amount' do
        expect(item.taxable_amount).to eq(500.0)
      end

      it 'does not divide by zero' do
        expect { item }.not_to raise_error
      end
    end

    context 'blank total_amount (incomplete row)' do
      it 'initializes new columns to safe defaults and does not crash' do
        item = SalesInvoiceItem.new(
          sales_invoice: invoice, product: p18, line_type: 'product',
          quantity: 1, total_amount: 0,
          metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
        )
        item.valid?
        expect(item.supply_type).to eq('intra_state')
        expect(item.cgst_amount).to eq(0)
        expect(item.igst_amount).to eq(0)
      end
    end

    context 'same state name with different casing' do
      # supply_type determination does .strip.downcase so 'West Bengal' == 'west bengal'
      let(:mixed_case_customer) do
        create(:gst_customer, organisation: org, state: 'WEST BENGAL', state_code: '19')
      end

      it 'correctly identifies as intra_state despite casing' do
        inv = SalesInvoice.create!(
          organisation: org, customer: mixed_case_customer, user: user,
          invoice_date: Date.today, status: 'draft',
          total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        item = build_item(inv, product: p18, qty: 1, total: 118.0)
        expect(item.supply_type).to eq('intra_state')
        expect(item.igst_amount).to eq(0.0)
        expect(item.cgst_amount).to be > 0
      end
    end

    context 'state with leading/trailing whitespace' do
      let(:spaced_customer) do
        create(:gst_customer, organisation: org, state: '  West Bengal  ', state_code: '19')
      end

      it 'trims whitespace and identifies as intra_state' do
        inv = SalesInvoice.create!(
          organisation: org, customer: spaced_customer, user: user,
          invoice_date: Date.today, status: 'draft',
          total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
        )
        item = build_item(inv, product: p18, qty: 1, total: 118.0)
        expect(item.supply_type).to eq('intra_state')
      end
    end
  end
end