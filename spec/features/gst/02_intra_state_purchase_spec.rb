# spec/features/gst/02_intra_state_purchase_spec.rb
#
# Feature: Intra-state purchase invoice GST (CGST + SGST)
# Drives Chrome to create a purchase invoice from a West Bengal supplier,
# confirm it, and verify CGST+SGST split in the item record and ITC register.

require 'rails_helper'

RSpec.describe 'Intra-state Purchase Invoice (CGST + SGST)', type: :feature, js: true do
  include CapybaraHelpers

  # ── Test data ──────────────────────────────────────────────────────────
  let!(:org)      { create(:organisation, state: 'West Bengal', state_code: '19') }
  let!(:admin)    { create(:user, organisation: org, role: :admin,
                            email: 'admin@test.com', password: 'password123') }
  let!(:supplier) { create(:gst_supplier, :intra_state, organisation: org,
                            name: 'Sharma Paints WB') }
  let!(:product)  { create(:gst_product, :gst_18,
                            description: 'Asian Paints Emulsion 20L',
                            hsn_code: '32081090') }

  before do
    product.enrol_in!(org)
    sign_in_as(admin)
  end

  # ── Scenario 1: Create and confirm ────────────────────────────────────
  scenario 'Creates purchase invoice and confirms — CGST+SGST split applied' do
    visit new_purchasing_purchase_invoice_path

    # Fill supplier autocomplete
    fill_in 'supplier-search-input', with: 'Sharma'
    within('#supplier-ac-dropdown') do
      first('li, div', text: 'Sharma Paints WB', wait: 5).click
    end

    fill_in 'Delivery Date', with: (Date.today + 7).strftime('%Y-%m-%d')

    # Fill first item row (row 0 is pre-rendered)
    within(all('tr[data-row], .item-row').first) do
      find('.product-search-input').set('Asian Paints')
      within(find('.ac-dropdown, [id*="dropdown"]', visible: true)) do
        first('div, li', text: 'Asian Paints', wait: 5).click
      end
      find('input[name*="quantity"]').set('20')
      # Enter GST-inclusive total: 20 × ₹1180 = ₹23,600
      find('input.total-editable, input[name*="total_amount"]').set('23600')
    end

    click_button 'Save Draft'
    expect(page).to have_current_path(%r{/purchasing/purchase_invoices/\d+})
    expect(page).to have_text('Draft')

    # Confirm the invoice
    click_button 'Confirm & Update Stock'
    expect(page).to have_text('confirmed', wait: 5)

    # ── Verify the DB record ──────────────────────────────────────────
    item = PurchaseInvoiceItem.last
    aggregate_failures 'GST column values' do
      expect(item.supply_type).to    eq('intra_state')
      expect(item.gst_rate).to       eq(18.0)
      expect(item.taxable_amount).to eq(20000.00)
      expect(item.tax_amount).to     eq(3600.00)
      expect(item.cgst_amount).to    eq(1800.00)
      expect(item.sgst_amount).to    eq(1800.00)
      expect(item.igst_amount).to    eq(0.00)
    end

    # ── Verify totals on the invoice show page ──────────────────────
    expect(page).to have_text('20,000')  # taxable
    expect(page).to have_text('3,600')   # tax
    expect(page).to have_text('23,600')  # total
  end

  # ── Scenario 2: ITC Register reflects the new item ────────────────
  scenario 'Confirmed invoice appears in ITC register with CGST and SGST split' do
    # Create confirmed invoice via model (faster — avoids duplicate UI steps)
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: supplier, user: admin,
      invoice_date: Date.today, delivery_date: Date.today + 7,
      status: 'draft', total_amount: 0,
      total_taxable_amount: 0, total_tax_amount: 0
    )
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: product,
      quantity: 20, unit_rate: 0, total_amount: 23600.0,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    inv.confirm!(admin)

    visit accounting_gst_itc_path(month: Date.today.month, year: Date.today.year)

    expect(page).to have_text('Input Tax Credit Register')

    # The row should show CGST and SGST, not IGST
    within('table tbody tr', wait: 5) do
      expect(page).to have_text('18')          # GST rate column
      expect(page).to have_text('20,000')      # taxable
      expect(page).to have_text('1,800')       # CGST
      # IGST column should show '—'
      expect(page).to have_text('—')
    end

    # Summary cards by rate
    expect(page).to have_text('1,800', minimum: 2)  # CGST + SGST both 1800
    expect(page).to have_text('3,600')               # Total ITC
  end

  # ── Scenario 3: Dashboard shows correct ITC ───────────────────────
  scenario 'GST dashboard ITC card shows CGST and SGST from intra-state purchase' do
    inv = PurchaseInvoice.create!(
      organisation: org, supplier: supplier, user: admin,
      invoice_date: Date.today, delivery_date: Date.today + 7,
      status: 'draft', total_amount: 0,
      total_taxable_amount: 0, total_tax_amount: 0
    )
    PurchaseInvoiceItem.create!(
      purchase_invoice: inv, product: product,
      quantity: 20, unit_rate: 0, total_amount: 23600.0,
      gst_rate: 0, taxable_amount: 0, tax_amount: 0,
      discount_percent: 0, discount_amount: 0,
      supply_type: 'intra_state',
      cgst_amount: 0, sgst_amount: 0, igst_amount: 0, metadata: {}
    )
    inv.confirm!(admin)

    go_to_gst_dashboard(month: Date.today.month, year: Date.today.year)

    # ITC card should show ₹3,600
    within('.gst-summary-card', text: /Input Tax Credit/i, wait: 5) do
      expect(page).to have_text('3,600')
    end

    # Tax head breakdown table — CGST row
    within('table') do
      within('tr', text: 'CGST') do
        expect(page).to have_text('1,800')
      end
      within('tr', text: 'SGST') do
        expect(page).to have_text('1,800')
      end
      within('tr', text: 'IGST') do
        # No IGST — should show 0 or —
        expect(page).to have_text(/0\.00|—/)
      end
    end
  end
end
