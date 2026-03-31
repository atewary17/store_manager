# spec/features/gst/04_sales_invoice_gst_spec.rb
#
# Feature: Sales invoice GST — intra-state (CGST+SGST) and inter-state (IGST)
# Covers: B2C, B2B, inter-state IGST output, GSTR-1 placement

require 'rails_helper'

RSpec.describe 'Sales Invoice GST', type: :feature, js: true do
  include CapybaraHelpers

  let!(:org)         { create(:organisation, state: 'West Bengal', state_code: '19') }
  let!(:admin)       { create(:user, organisation: org, role: :admin,
                               email: 'admin@test.com', password: 'password123') }
  let!(:wb_customer) { create(:gst_customer, :intra_state, organisation: org,
                               name: 'Local Contractor Kolkata') }
  let!(:b2b_customer){ create(:gst_customer, :intra_state, :b2b, organisation: org,
                               name: 'Kolkata Hardware Pvt Ltd') }
  let!(:bi_customer) { create(:gst_customer, :inter_state, organisation: org,
                               name: 'Bihar Construction Co') }
  let!(:paint)       { create(:gst_product, :gst_18,
                               description: 'Asian Paints Emulsion',
                               hsn_code: '32081090') }
  let!(:steel)       { create(:gst_product, :gst_12,
                               description: 'MS Rod 10mm',
                               hsn_code: '72141000') }

  before { sign_in_as(admin) }

  # ── Helper: build confirmed sales invoice via model ─────────────────
  def make_sale(customer:, product:, qty:, total:, cgst_pct: 9.0, sgst_pct: 9.0)
    inv = SalesInvoice.create!(
      organisation: org, customer: customer, user: admin,
      invoice_date: Date.today, status: 'draft',
      total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
    )
    SalesInvoiceItem.create!(
      sales_invoice: inv, product: product, line_type: 'product',
      quantity: qty, total_amount: total, discount_percent: 0,
      metadata: { 'cgst_percent' => cgst_pct, 'sgst_percent' => sgst_pct }
    )
    inv.confirm!(admin)
    inv.reload
  end

  # ═══════════════════════════════════════════════════════════════════
  # INTRA-STATE SALES
  # ═══════════════════════════════════════════════════════════════════

  scenario 'Intra-state B2C sale — CGST+SGST split, appears in GSTR-1 B2C' do
    inv = make_sale(customer: wb_customer, product: paint, qty: 5, total: 5900.0)
    item = inv.sales_invoice_items.first

    aggregate_failures 'intra-state sale columns' do
      expect(item.supply_type).to   eq('intra_state')
      expect(item.gst_rate).to      eq(18.0)
      expect(item.taxable_amount).to be_within(1.0).of(5000.0)
      expect(item.cgst_amount).to   be_within(1.0).of(450.0)
      expect(item.sgst_amount).to   be_within(1.0).of(450.0)
      expect(item.igst_amount).to   eq(0.0)
    end

    # Navigate to GSTR-1
    visit accounting_gstr1_path(month: Date.today.month, year: Date.today.year)

    # B2C section — customer has no GSTIN
    expect(page).to have_text('B2C')
    within('table', text: /B2C|Unregistered/) do
      expect(page).to have_text('Local Contractor Kolkata')
    end

    # B2B section must NOT contain this customer
    within('table', text: /B2B|Registered/) do
      expect(page).to have_no_text('Local Contractor Kolkata')
    end
  end

  scenario 'Intra-state B2B sale — appears in GSTR-1 B2B with GSTIN' do
    inv = make_sale(customer: b2b_customer, product: steel, qty: 20, total: 22400.0,
                    cgst_pct: 6.0, sgst_pct: 6.0)
    item = inv.sales_invoice_items.first

    aggregate_failures '12% B2B sale' do
      expect(item.supply_type).to   eq('intra_state')
      expect(item.gst_rate).to      eq(12.0)
      expect(item.cgst_amount).to   be_within(1.0).of(1200.0)
      expect(item.sgst_amount).to   be_within(1.0).of(1200.0)
      expect(item.igst_amount).to   eq(0.0)
    end

    visit accounting_gstr1_path(month: Date.today.month, year: Date.today.year)

    within('table', text: /B2B|Registered/) do
      expect(page).to have_text('Kolkata Hardware Pvt Ltd')
      # Should display GSTIN
      expect(page).to have_text(b2b_customer.gstin)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # INTER-STATE SALE (IGST output)
  # ═══════════════════════════════════════════════════════════════════

  scenario 'Inter-state sale to Bihar — IGST output, CGST/SGST zero' do
    inv = make_sale(customer: bi_customer, product: paint, qty: 10, total: 11800.0)
    item = inv.sales_invoice_items.first

    aggregate_failures 'inter-state sale IGST' do
      expect(item.supply_type).to   eq('inter_state')
      expect(item.gst_rate).to      eq(18.0)
      expect(item.taxable_amount).to be_within(1.0).of(10000.0)
      expect(item.cgst_amount).to   eq(0.0)    # MUST be zero
      expect(item.sgst_amount).to   eq(0.0)    # MUST be zero
      expect(item.igst_amount).to   be_within(1.0).of(1800.0)
    end

    # Metadata also updated
    expect(item.metadata['igst_percent'].to_f).to eq(18.0)
    expect(item.metadata['cgst_percent'].to_f).to eq(0.0)
    expect(item.metadata['igst_amount'].to_f).to  be_within(1.0).of(1800.0)
  end

  scenario 'GSTR-1 summary cards include IGST output from inter-state sale' do
    make_sale(customer: bi_customer, product: paint, qty: 10, total: 11800.0)

    visit accounting_gstr1_path(month: Date.today.month, year: Date.today.year)

    # Summary card — total tax should include IGST
    expect(page).to have_text('1,800')  # total tax from this sale
  end

  # ═══════════════════════════════════════════════════════════════════
  # GST DASHBOARD — output tax breakdown
  # ═══════════════════════════════════════════════════════════════════

  scenario 'Dashboard shows correct output tax breakdown with mixed sales' do
    # Intra-state: CGST 450, SGST 450 (total 900)
    make_sale(customer: wb_customer, product: paint, qty: 5, total: 5900.0)
    # Inter-state: IGST 1800 (total 1800)
    make_sale(customer: bi_customer, product: paint, qty: 10, total: 11800.0)

    go_to_gst_dashboard(month: Date.today.month, year: Date.today.year)

    within('table') do
      within('tr', text: 'CGST') do
        expect(page).to have_text('450')
      end
      within('tr', text: 'SGST') do
        expect(page).to have_text('450')
      end
      within('tr', text: 'IGST') do
        expect(page).to have_text('1,800')
      end
    end

    # Output tax card: 450 + 450 + 1800 = 2700
    within(:css, '*', text: 'Output Tax') do
      expect(page).to have_text('2,700')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # WALK-IN SALE (no customer)
  # ═══════════════════════════════════════════════════════════════════

  scenario 'Walk-in sale (no customer) defaults to intra-state CGST+SGST' do
    inv = SalesInvoice.create!(
      organisation: org, customer: nil, user: admin,
      invoice_date: Date.today, status: 'draft',
      total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
    )
    SalesInvoiceItem.create!(
      sales_invoice: inv, product: paint, line_type: 'product',
      quantity: 3, total_amount: 3540.0, discount_percent: 0,
      metadata: { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 }
    )
    inv.confirm!(admin)
    item = inv.sales_invoice_items.first

    expect(item.supply_type).to  eq('intra_state')
    expect(item.cgst_amount).to  be > 0
    expect(item.igst_amount).to  eq(0.0)

    # Appears in GSTR-1 B2C (no customer = no GSTIN)
    visit accounting_gstr1_path(month: Date.today.month, year: Date.today.year)
    within('table', text: /B2C|Unregistered/) do
      expect(page).to have_text('Walk-in')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # HSN SUMMARY
  # ═══════════════════════════════════════════════════════════════════

  scenario 'HSN summary shows correct sales HSN with gst_rate grouping' do
    make_sale(customer: wb_customer, product: paint, qty: 5,  total: 5900.0)
    make_sale(customer: bi_customer, product: steel, qty: 20, total: 22400.0,
              cgst_pct: 6.0, sgst_pct: 6.0)

    visit accounting_gst_hsn_path(month: Date.today.month, year: Date.today.year)

    # Sales panel
    within('div', text: 'Sales (Outward)') do
      expect(page).to have_text('32081090')  # paint HSN
      expect(page).to have_text('72141000')  # steel HSN
    end
  end
end
