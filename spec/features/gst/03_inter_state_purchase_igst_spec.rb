# spec/features/gst/03_inter_state_purchase_igst_spec.rb
#
# Feature: Inter-state purchase invoice GST (IGST only)
# Chrome test: Maharashtra supplier → West Bengal org
# Verifies: supply_type = inter_state, IGST set, CGST/SGST = 0

require 'rails_helper'

RSpec.describe 'Inter-state Purchase Invoice (IGST)', type: :feature, js: true do
  include CapybaraHelpers

  let!(:org)         { create(:organisation, state: 'West Bengal', state_code: '19') }
  let!(:admin)       { create(:user, organisation: org, role: :admin,
                               email: 'admin@test.com', password: 'password123') }
  let!(:mh_supplier) { create(:gst_supplier, :inter_state, organisation: org,
                               name: 'Ultratech Mumbai Dist') }
  let!(:cement)      { create(:gst_product, :gst_28,
                               description: 'OPC Cement 50kg',
                               hsn_code: '25010010') }
  let!(:paint)       { create(:gst_product, :gst_18,
                               description: 'Asian Paints 20L') }

  before do
    cement.enrol_in!(org)
    paint.enrol_in!(org)
    sign_in_as(admin)
  end

  # Helper: create and confirm an inter-state purchase via model
  def create_inter_state_purchase(product:, qty:, total:)
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: mh_supplier, user: admin,
      invoice_date: Date.today, delivery_date: Date.today + 7,
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
    inv.reload
  end

  # ── Scenario 1: UI — create and confirm inter-state invoice ─────────
  scenario 'Creates inter-state purchase via UI — IGST applied, CGST/SGST zero' do
    visit new_purchasing_purchase_invoice_path

    # Select inter-state supplier (Maharashtra)
    fill_in 'supplier-search-input', with: 'Ultratech'
    within('#supplier-ac-dropdown') do
      first('li, div', text: 'Ultratech Mumbai Dist', wait: 5).click
    end

    fill_in 'Delivery Date', with: (Date.today + 7).strftime('%Y-%m-%d')

    # Fill item row: 50 bags cement @ ₹22,400 incl. 28% GST
    within(all('tr[data-row], .item-row').first) do
      find('.product-search-input').set('OPC Cement')
      within(find('.ac-dropdown, [id*="dropdown"]', visible: true)) do
        first('div, li', text: 'OPC Cement', wait: 5).click
      end
      find('input[name*="quantity"]').set('50')
      find('input.total-editable, input[name*="total_amount"]').set('22400')
    end

    click_button 'Save Draft'
    expect(page).to have_current_path(%r{/purchasing/purchase_invoices/\d+})

    click_button 'Confirm & Update Stock'
    expect(page).to have_text('confirmed', wait: 5)

    # Verify DB
    item = PurchaseInvoiceItem.last
    aggregate_failures 'IGST inter-state values' do
      expect(item.supply_type).to    eq('inter_state')
      expect(item.gst_rate).to       eq(28.0)
      expect(item.taxable_amount).to eq(17500.00)
      expect(item.tax_amount).to     eq(4900.00)
      expect(item.cgst_amount).to    eq(0.00)   # MUST be zero
      expect(item.sgst_amount).to    eq(0.00)   # MUST be zero
      expect(item.igst_amount).to    eq(4900.00)
    end

    # Verify metadata in sync
    expect(item.metadata['supply_type']).to eq('inter_state')
    expect(item.metadata['igst_amount'].to_f).to eq(4900.00)
    expect(item.metadata['cgst_amount'].to_f).to eq(0.00)
  end

  # ── Scenario 2: ITC Register shows IGST column, not CGST/SGST ──────
  scenario 'ITC register shows IGST in the IGST column, CGST and SGST show dash' do
    create_inter_state_purchase(product: cement, qty: 50, total: 22400.0)

    visit accounting_gst_itc_path(month: Date.today.month, year: Date.today.year)

    within('table tbody') do
      # Should have one row
      expect(page).to have_css('tr', minimum: 1)

      within('tr:first-child') do
        # GST rate
        expect(page).to have_text('28')
        # Taxable amount
        expect(page).to have_text('17,500')
        # CGST column → dash (index 6: Date, Invoice#, Supplier, Product/HSN, GST%, Taxable, CGST)
        expect(all('td')[6].text).to match(/—|0\.00/)
        # SGST column → dash
        expect(all('td')[7].text).to match(/—|0\.00/)
        # IGST column → 4,900
        expect(all('td')[8].text).to have_text('4,900')
      end
    end

    # Total ITC card
    expect(page).to have_text('4,900')
  end

  # ── Scenario 3: Multiple items — mixed rates, all inter-state ───────
  scenario 'Multiple inter-state items both get IGST, correct totals' do
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: mh_supplier, user: admin,
      invoice_date: Date.today, delivery_date: Date.today + 7,
      status: 'draft', total_amount: 0,
      total_taxable_amount: 0, total_tax_amount: 0
    )
    # Item 1: 28% cement — taxable 17500, IGST 4900
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: cement,
      quantity: 50, unit_rate: 0, total_amount: 22400.0,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    # Item 2: 18% paint — taxable 10000, IGST 1800
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: paint,
      quantity: 10, unit_rate: 0, total_amount: 11800.0,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    inv.confirm!(admin)

    items = inv.purchase_invoice_items.reload
    items.each do |item|
      expect(item.supply_type).to eq('inter_state')
      expect(item.cgst_amount).to eq(0.0)
      expect(item.sgst_amount).to eq(0.0)
      expect(item.igst_amount).to eq(item.tax_amount)
    end

    # Dashboard — IGST ITC total = 4900 + 1800 = 6700
    go_to_gst_dashboard(month: Date.today.month, year: Date.today.year)

    within('table') do
      within('tr', text: 'IGST') do
        expect(page).to have_text('6,700')
      end
      within('tr', text: 'CGST') do
        expect(page).to have_text(/0\.00|—/)
      end
    end
  end

  # ── Scenario 4: GSTR-3B shows IGST ITC in Section 4 ───────────────
  scenario 'GSTR-3B Section 4 shows IGST ITC from inter-state purchase' do
    create_inter_state_purchase(product: cement, qty: 50, total: 22400.0)

    visit accounting_gstr3b_path(month: Date.today.month, year: Date.today.year)

    expect(page).to have_text('GSTR-3B')

    # Section 4: ITC Available — Inward supplies (others)
    within('#gstr3b-itc-table') do
      # The row that shows inward supplies ITC should include 4900
      expect(page).to have_text('4,900')
    end
  end
end
