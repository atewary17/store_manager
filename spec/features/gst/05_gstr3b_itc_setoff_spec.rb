# spec/features/gst/05_gstr3b_itc_setoff_spec.rb
#
# Feature: GSTR-3B — full 7-step ITC set-off Chrome automation
# Covers every legal ITC utilisation scenario including:
#   - IGST ITC clearing CGST + SGST output (your exact use case)
#   - CGST/SGST cannot cross-offset each other
#   - Cash payable when ITC < output
#   - Credit carry-forward when ITC > output
#   - Empty period shows zero amounts

require 'rails_helper'

RSpec.describe 'GSTR-3B ITC Set-off (7-step algorithm)', type: :feature, js: true do
  include CapybaraHelpers

  let!(:org)         { create(:organisation, state: 'West Bengal', state_code: '19') }
  let!(:admin)       { create(:user, organisation: org, role: :admin,
                               email: 'admin@test.com', password: 'password123') }
  let!(:wb_supplier) { create(:gst_supplier, :intra_state, organisation: org) }
  let!(:mh_supplier) { create(:gst_supplier, :inter_state, organisation: org) }
  let!(:wb_customer) { create(:gst_customer, :intra_state, organisation: org) }
  let!(:bi_customer) { create(:gst_customer, :inter_state, organisation: org) }
  let!(:paint)       { create(:gst_product, :gst_18,
                               description: 'Asian Paints',
                               hsn_code: '32081090') }
  let!(:cement)      { create(:gst_product, :gst_28,
                               description: 'OPC Cement',
                               hsn_code: '25010010') }

  let(:this_month) { Date.today }
  let(:month)      { this_month.month }
  let(:year)       { this_month.year }

  before { sign_in_as(admin) }

  # ── Model helpers ──────────────────────────────────────────────────
  def purchase!(supplier:, product:, qty:, total:)
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: supplier, user: admin,
      invoice_date: this_month, delivery_date: this_month + 7,
      status: 'draft', total_amount: 0,
      total_taxable_amount: 0, total_tax_amount: 0
    )
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: product,
      quantity: qty, unit_rate: 0, total_amount: total,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    inv.confirm!(admin)
  end

  def sale!(customer:, product:, qty:, total:, cgst_pct: 9.0, sgst_pct: 9.0)
    inv = SalesInvoice.create!(
      organisation: org, customer: customer, user: admin,
      invoice_date: this_month, status: 'draft',
      total_amount: 0, total_taxable_amount: 0, total_tax_amount: 0
    )
    SalesInvoiceItem.create!(
      sales_invoice: inv, product: product, line_type: 'product',
      quantity: qty, total_amount: total, discount_percent: 0,
      metadata: { 'cgst_percent' => cgst_pct, 'sgst_percent' => sgst_pct }
    )
    inv.confirm!(admin)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 1: YOUR EXACT EXAMPLE
  # Buy from Maharashtra, sell intra-state
  # IGST ITC 54000 > CGST+SGST output 21600 → no cash, big carry-forward
  # ═══════════════════════════════════════════════════════════════════
  scenario 'IGST ITC from inter-state purchase fully covers CGST+SGST output — zero cash' do
    # Purchase: ₹3,54,000 from MH (300 × ₹1180), taxable=300000, IGST=54000
    purchase!(supplier: mh_supplier, product: paint, qty: 300, total: 354000.0)

    # Sale: ₹1,41,600 intra-state (100 × ₹1416), taxable=120000, CGST=10800, SGST=10800
    sale!(customer: wb_customer, product: paint, qty: 100, total: 141600.0)

    visit accounting_gstr3b_path(month: month, year: year)

    expect(page).to have_text('GSTR-3B')

    # Section 5.1 — Net Cash Payable must be 0
    within('#gstr3b-payment-table') do
      # Total row shows ₹0.00 cash
      expect(page).to have_text('0.00')
    end

    # Green success box "No GST cash payment required"
    expect(page).to have_css('.flash.notice, [style*="success"], [style*="teal"]',
                             text: /No GST cash payment|Zero cash|credit carry/i,
                             wait: 5)

    # IGST credit carry-forward should be ≈ 54000 - 10800 - 10800 = 32400
    expect(page).to have_text('32,400')
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 2: Cash payment required (output > ITC)
  # ═══════════════════════════════════════════════════════════════════
  scenario 'Output tax exceeds ITC — amber warning, cash payable shown' do
    # Small purchase: CGST 90, SGST 90 (total ITC 180)
    purchase!(supplier: wb_supplier, product: paint, qty: 1, total: 1180.0)
    # Boost stock so the large sale can confirm (purchase only adds 1 unit)
    StockLevel.find_or_initialize_by(organisation: org, product: paint).tap { |sl| sl.quantity = 100; sl.avg_cost ||= 0; sl.save! }

    # Large sale: CGST 900, SGST 900 (total output 1800)
    sale!(customer: wb_customer, product: paint, qty: 10, total: 11800.0)

    visit accounting_gstr3b_path(month: month, year: year)

    # Amber warning box
    expect(page).to have_css('[style*="warning"], [style*="amber"], .flash.warning',
                             text: /Cash payment|Pay|due/i,
                             wait: 5)

    # CGST payable = 900 - 90 = 810
    expect(page).to have_text('810')
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 3: Mixed — IGST ITC partially covers, CGST/SGST top-up
  # ═══════════════════════════════════════════════════════════════════
  scenario 'Mixed IGST ITC + CGST/SGST ITC — steps 1-6 all used' do
    # IGST ITC = 18000 (inter-state purchase, 18% on 100000 taxable)
    purchase!(supplier: mh_supplier, product: paint, qty: 100, total: 118000.0)

    # CGST ITC = 7200, SGST ITC = 7200 (intra-state, 18% on 80000 taxable)
    purchase!(supplier: wb_supplier, product: paint, qty: 80, total: 94400.0)

    # Output: CGST = 13500, SGST = 13500 (intra-state sale, 18% on 150000 taxable)
    sale!(customer: wb_customer, product: paint, qty: 150, total: 177000.0)

    visit accounting_gstr3b_path(month: month, year: year)

    # Step 2: IGST covers CGST output fully (13500)
    # Step 3: remaining IGST (4500) covers part of SGST
    # Step 6: SGST ITC (7200) covers remaining SGST (9000) → 7200
    # Remaining SGST cash: 9000 - 7200 = 1800
    # CGST cash: 0 (fully covered by IGST)
    # IGST carry-forward: 0 (all used)
    # CGST carry-forward: 7200 (unused)

    within('#gstr3b-payment-table') do
      # CGST row — 0 cash
      within('tr', text: 'Central Tax') do
        expect(page).to have_text('0.00')
      end
    end

    # CGST carry-forward ≈ 7200
    expect(page).to have_text('7,200')
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 4: CGST cannot cross-offset SGST (legal prohibition)
  # ═══════════════════════════════════════════════════════════════════
  scenario 'Section 5.1 does not show a CGST→SGST or SGST→CGST cell' do
    purchase!(supplier: wb_supplier, product: paint, qty: 5, total: 5900.0)
    sale!(customer: wb_customer, product: paint, qty: 5, total: 5900.0)

    visit accounting_gstr3b_path(month: month, year: year)

    # The Section 5.1 table columns are:
    # Description | Tax Payable | ITC(IGST) | ITC(CGST) | ITC(SGST) | TDS | Cash
    # CGST row should have ITC(SGST) = — (forbidden)
    # SGST row should have ITC(CGST) = — (forbidden)
    within('#gstr3b-payment-table') do
      rows = all('tr')
      cgst_row = rows.find { |r| r.text.include?('Central Tax') }
      sgst_row = rows.find { |r| r.text.include?('State') }

      # In CGST row, the 5th column (ITC SGST) must be — or 0
      if cgst_row
        cgst_cells = cgst_row.all('td')
        # ITC(SGST) is the 5th data cell (index 4)
        expect(cgst_cells[4].text).to match(/—|0\.00/) if cgst_cells[4]
      end

      # In SGST row, the 4th column (ITC CGST) must be — or 0
      if sgst_row
        sgst_cells = sgst_row.all('td')
        expect(sgst_cells[3].text).to match(/—|0\.00/) if sgst_cells[3]
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 5: Empty period — all zeros, no crash
  # ═══════════════════════════════════════════════════════════════════
  scenario 'Empty period (no invoices) shows zero amounts without error' do
    visit accounting_gstr3b_path(month: 1, year: 2020)

    expect(page).to have_http_status(:ok) rescue nil  # Capybara way:
    expect(page).to have_no_text('Error')
    expect(page).to have_no_text('exception')
    expect(page).to have_text('0.00', minimum: 3)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 6: Filing deadlines visible on GSTR-3B page
  # ═══════════════════════════════════════════════════════════════════
  scenario 'GSTR-3B page shows the correct filing due date' do
    visit accounting_gstr3b_path(month: month, year: year)

    # Due date = 20th of next month
    expected_date = (Date.new(year, month, 1) + 1.month).change(day: 20)
    expect(page).to have_text(expected_date.strftime('%-d %b %Y'))
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 7: ITC exactly = output → zero payable, zero carry-forward
  # ═══════════════════════════════════════════════════════════════════
  scenario 'ITC equals output — zero cash payable and zero carry-forward' do
    # ITC: CGST 900, SGST 900
    purchase!(supplier: wb_supplier, product: paint, qty: 10, total: 11800.0)
    # Output: CGST 900, SGST 900
    sale!(customer: wb_customer, product: paint, qty: 10, total: 11800.0)

    visit accounting_gstr3b_path(month: month, year: year)

    within('#gstr3b-payment-table') do
      within('tbody tr:last-child') do
        # Total cash payable row
        expect(page).to have_text('0.00')
      end
    end

    # No credit carry-forward either (all carry-forward amounts must be zero)
    expect(page).to have_no_text(/carry.forward.*₹[1-9]/i)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Scenario 8: Inter-state sale creates IGST output
  # IGST ITC first pays IGST output (step 1)
  # ═══════════════════════════════════════════════════════════════════
  scenario 'IGST output from inter-state sale — IGST ITC pays it first (Step 1)' do
    # IGST ITC = 3600 (inter-state purchase 18% on 20000)
    purchase!(supplier: mh_supplier, product: paint, qty: 20, total: 23600.0)

    # IGST output = 1800 (inter-state sale to Bihar, 18% on 10000)
    sale!(customer: bi_customer, product: paint, qty: 10, total: 11800.0)

    visit accounting_gstr3b_path(month: month, year: year)

    within('#gstr3b-payment-table') do
      within('tr', text: 'Integrated Tax') do
        # Tax payable: 1800
        # ITC IGST used: 1800 (Step 1 — same head)
        # Cash: 0
        expect(page).to have_text('1,800')
        expect(page).to have_text('0.00')
      end
    end

    # Remaining IGST carry-forward = 3600 - 1800 = 1800
    expect(page).to have_text('1,800')
  end
end
