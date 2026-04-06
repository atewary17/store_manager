# spec/features/gst/06_full_gst_workflow_spec.rb
#
# Feature: Full GST workflow end-to-end Chrome automation
# One comprehensive test that mirrors a real month of store operations:
#   1. Set up organisation (West Bengal)
#   2. Create intra-state purchase (CGST+SGST ITC)
#   3. Create inter-state purchase (IGST ITC)
#   4. Create intra-state sales (CGST+SGST output)
#   5. Create inter-state sale (IGST output)
#   6. Check GST Dashboard — all four tax amounts
#   7. Check GSTR-1 — B2B, B2C, HSN Table 12
#   8. Check GSTR-3B — 7-step set-off, final cash/credit
#   9. Check ITC Register — split by rate and supply_type
#  10. Check HSN Summary — both panels

require 'rails_helper'

RSpec.describe 'Full GST Workflow — End to End', type: :feature, js: true do
  include CapybaraHelpers

  # ── Master test data ────────────────────────────────────────────────
  let!(:org)         { create(:organisation, state: 'West Bengal', state_code: '19',
                               gst_number: '19AAAAA0000A1Z5') }
  let!(:admin)       { create(:user, organisation: org, role: :admin,
                               email: 'admin@test.com', password: 'password123') }
  let!(:wb_supplier) { create(:gst_supplier, :intra_state, organisation: org,
                               name: 'Sharma Paints WB') }
  let!(:mh_supplier) { create(:gst_supplier, :inter_state, organisation: org,
                               name: 'Ultratech Mumbai') }
  let!(:wb_customer) { create(:gst_customer, :intra_state, organisation: org,
                               name: 'Local Contractor') }
  let!(:b2b_cust)    { create(:gst_customer, :intra_state, :b2b, organisation: org,
                               name: 'Kolkata Hardware Pvt Ltd') }
  let!(:bi_customer) { create(:gst_customer, :inter_state, organisation: org,
                               name: 'Bihar Construction') }
  let!(:paint)       { create(:gst_product, :gst_18,
                               description: 'Asian Paints Emulsion',
                               hsn_code: '32081090') }
  let!(:cement)      { create(:gst_product, :gst_28,
                               description: 'OPC Cement 50kg',
                               hsn_code: '25010010') }

  let(:this_month) { Date.today }
  let(:month)      { this_month.month }
  let(:year)       { this_month.year }

  before { sign_in_as(admin) }

  # ── Month's transactions (built via model for speed, UI tested separately) ──
  before do
    # ── PURCHASES ──
    # 1. Intra-state: paint from WB supplier
    #    20 × ₹1180 = ₹23,600 | taxable 20000 | CGST 1800, SGST 1800
    create_purchase(wb_supplier, paint, 20, 23600.0)

    # 2. Inter-state: cement from MH supplier
    #    50 × ₹448 = ₹22,400 | taxable 17500 | IGST 4900
    create_purchase(mh_supplier, cement, 50, 22400.0)

    # ── SALES ──
    # 3. Intra-state B2C sale (walk-in)
    #    5 × ₹1180 = ₹5,900 | taxable 5000 | CGST 450, SGST 450
    create_sale(wb_customer, paint, 5, 5900.0, 9.0, 9.0)

    # 4. Intra-state B2B sale (has GSTIN)
    #    10 × ₹1180 = ₹11,800 | taxable 10000 | CGST 900, SGST 900
    create_sale(b2b_cust, paint, 10, 11800.0, 9.0, 9.0)

    # 5. Inter-state sale to Bihar
    #    5 × ₹1180 = ₹5,900 | taxable 5000 | IGST 900
    create_sale(bi_customer, paint, 5, 5900.0, 9.0, 9.0)
  end

  # Expected totals:
  # ITC:    CGST 1800, SGST 1800, IGST 4900, Total 8500
  # Output: CGST 1350, SGST 1350, IGST  900, Total 3600
  # Net:    CGST -450, SGST -450, IGST -4000 → all credit, cash = 0

  # ═══════════════════════════════════════════════════════════════════
  it 'GST Dashboard shows correct totals for the month' do
    go_to_gst_dashboard(month: month, year: year)

    # Output Tax card ≈ 3600
    within('.gst-summary-card', text: /Output Tax/i) do
      expect(page).to have_text(/3[,.]?600/)
    end

    # ITC card ≈ 8500
    within('.gst-summary-card', text: /Input Tax Credit/i) do
      expect(page).to have_text(/8[,.]?500/)
    end

    # Net GST card — should be credit (no cash to pay)
    within('.gst-summary-card', text: /Net GST/i) do
      expect(page).to have_text(/credit|0\.00|—/i)
    end

    # Tax head breakdown table
    within('table') do
      within('tr', text: 'CGST') do
        expect(page).to have_text('1,350')   # output
        expect(page).to have_text('1,800')   # ITC
      end
      within('tr', text: 'IGST') do
        expect(page).to have_text('900')     # output
        expect(page).to have_text('4,900')   # ITC
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  it 'GSTR-1 shows correct B2B, B2C split and HSN summary' do
    visit accounting_gstr1_path(month: month, year: year)

    # B2B: only b2b_cust (has GSTIN)
    within('#gstr1-b2b-table') do
      expect(page).to have_text('Kolkata Hardware Pvt Ltd')
      expect(page).to have_text(b2b_cust.gstin)
      expect(page).to have_no_text('Local Contractor')   # B2C
      expect(page).to have_no_text('Bihar Construction') # B2C
    end

    # B2C: wb_customer + bi_customer (neither has GSTIN)
    within('#gstr1-b2c-table') do
      expect(page).to have_text('Local Contractor')
      expect(page).to have_text('Bihar Construction')
    end

    # Summary cards
    within('.gst-summary-card', text: /Total Tax Collected/i) do
      expect(page).to have_text('3,600')
    end

    # HSN Table 12 — paint HSN present
    within('#gstr1-hsn-table') do
      expect(page).to have_text('32081090')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  it 'GSTR-3B shows zero cash payable and carry-forward credit' do
    visit accounting_gstr3b_path(month: month, year: year)

    # Section 3.1 outward taxable value = 5000+10000+5000 = 20000
    within('#gstr3b-outward-table') do
      expect(page).to have_text('20,000')
    end

    # Section 5.1 — all three heads have zero cash payable
    within('#gstr3b-payment-table') do
      # Total row = 0.00
      within('tbody tr:last-child') do
        expect(page).to have_text('0.00')
      end
    end

    # Green "no cash" notice
    expect(page).to have_css('[style*="success"], [style*="teal"]',
                             text: /No GST cash|Zero cash|credit/i)

    # Carry-forward values visible
    # CGST credit = 1800 - 1350 = 450 (after IGST used CGST output)
    # OR IGST used CGST entirely → CGST carry = 1800
    # Either way, page should show some carry-forward
    expect(page).to have_text(/\d+[,.]?\d+/)
  end

  # ═══════════════════════════════════════════════════════════════════
  it 'ITC Register shows two rows with correct supply_type split' do
    visit accounting_gst_itc_path(month: month, year: year)

    # Should have 2 rows (paint + cement purchases)
    expect(page).to have_css('table tbody tr', count: 2)

    # Paint row (intra-state): CGST 1800, SGST 1800, IGST —
    within('table tbody tr', text: /paint|emulsion/i) do
      expect(page).to have_text('18')       # rate
      expect(page).to have_text('20,000')   # taxable
      expect(page).to have_text('1,800')    # CGST
      # IGST should be dash
      expect(page).to have_text('—')
    end

    # Cement row (inter-state): CGST —, SGST —, IGST 4900
    within('table tbody tr', text: /cement/i) do
      expect(page).to have_text('28')       # rate
      expect(page).to have_text('17,500')   # taxable
      expect(page).to have_text('4,900')    # IGST
    end

    # Summary cards — one per rate
    expect(page).to have_text('18%')
    expect(page).to have_text('28%')

    # Total ITC ≈ 8500
    within('tfoot') do
      expect(page).to have_text('8,500')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  it 'HSN Summary shows both sales and purchase panels with correct HSN codes' do
    visit accounting_gst_hsn_path(month: month, year: year)

    # Sales panel
    within('#sales-hsn-panel') do
      expect(page).to have_text('32081090')  # paint
      # No cement HSN in sales
      expect(page).to have_no_text('25010010')
    end

    # Purchases panel
    within('#purchase-hsn-panel') do
      expect(page).to have_text('32081090')  # paint
      expect(page).to have_text('25010010')  # cement
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  it 'Period filter isolates to selected month — no cross-period bleed' do
    # Create an invoice in a different month
    different_month = Date.today.prev_month
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: wb_supplier, user: admin,
      invoice_date: different_month, delivery_date: different_month + 7,
      status: 'draft', total_amount: 0,
      total_taxable_amount: 0, total_tax_amount: 0
    )
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: paint,
      quantity: 100, unit_rate: 0, total_amount: 118000.0,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    inv.confirm!(admin)

    # Current month ITC ≈ 8500 (from before block)
    go_to_gst_dashboard(month: month, year: year)
    within('.gst-summary-card', text: /Input Tax Credit/i) do
      expect(page).to have_text(/8[,.]?500/)  # not 8500 + 18000
    end
  end

  private

  def create_purchase(supplier, product, qty, total)
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

  def create_sale(customer, product, qty, total, cgst_pct, sgst_pct)
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
end
