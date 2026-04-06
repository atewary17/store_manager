# spec/support/capybara_helpers.rb
#
# Page-object helpers for MyStoreManager feature specs.
# Encapsulates repeated UI interactions so specs stay readable.

module CapybaraHelpers

  # ── Authentication ─────────────────────────────────────────────────────
  def sign_in_as(user)
    visit '/users/sign_in'
    fill_in 'Email Address', with: user.email
    fill_in 'Password',      with: user.password  # plaintext set in factory
    click_button 'Sign in to StoreERP'
    expect(page).to have_no_css('.alert-box'), "Login failed for #{user.email}"
  end

  def sign_out
    # Visit sign-out — Devise DELETE /users/sign_out
    visit destroy_user_session_path rescue nil
    visit '/users/sign_out'
  end

  # ── Organisation setup ─────────────────────────────────────────────────
  def set_organisation_state(org, state:, state_code:)
    visit edit_organisation_path(org)
    select state, from: 'State'
    fill_in 'State Code', with: state_code
    click_button 'Save'
    expect(page).to have_text('updated successfully')
  end

  # ── Navigation ─────────────────────────────────────────────────────────
  def go_to_gst_dashboard(month: nil, year: nil)
    visit '/accounting/gst'
    if month && year
      select Date::MONTHNAMES[month], from: 'month'
      select year.to_s,              from: 'year'
      click_button 'Go'
    end
    expect(page).to have_css('.page-title', text: 'GST Dashboard')
  end

  # ── Purchase Invoice ───────────────────────────────────────────────────

  # Opens the new purchase invoice form and fills supplier via the
  # autocomplete widget (type in the search box, wait for dropdown, click match).
  def start_purchase_invoice(supplier_name:, invoice_date: Date.today)
    visit new_purchasing_purchase_invoice_path
    # Supplier autocomplete
    fill_in 'supplier-search-input', with: supplier_name
    # Wait for dropdown to appear and click the first match
    within('#supplier-ac-dropdown') do
      first('div', text: supplier_name, wait: 5).click
    end
    # Invoice date
    fill_in 'Invoice Date', with: invoice_date.strftime('%Y-%m-%d')
    fill_in 'Delivery Date', with: (invoice_date + 7).strftime('%Y-%m-%d')
  end

  # Fills a purchase invoice item row.
  # row_index: 0-based index of the item row
  # Relies on the item row having a product search input and a qty/total input.
  def fill_purchase_item(row_index:, product_name:, qty:, total:)
    within(all('tr.item-row')[row_index]) do
      # Product autocomplete
      find('.product-search-input').fill_in(with: product_name)
      within(find('.ac-dropdown', visible: true)) do
        first('div', text: product_name, wait: 5).click
      end
      find('input[name$="[quantity]"]').fill_in(with: qty.to_s)
      # The total-editable field is the last numeric input in the row
      find('input.total-editable, input[name$="[total_amount]"]').fill_in(with: total.to_s)
    end
  end

  def save_and_confirm_purchase_invoice
    click_button 'Save Invoice'
    expect(page).to have_text('Purchase Invoice')  # on show page
    click_button 'Confirm Invoice'
    expect(page).to have_css('.badge', text: /confirmed/i)
  end

  # ── Sales Invoice ──────────────────────────────────────────────────────
  def start_sales_invoice(customer_name: nil, invoice_date: Date.today)
    visit new_sales_sales_invoice_path
    if customer_name
      fill_in 'customer-search-input', with: customer_name
      within('#customer-ac-dropdown') do
        first('div', text: customer_name, wait: 5).click
      end
    end
    fill_in 'Invoice Date', with: invoice_date.strftime('%Y-%m-%d')
  end

  def add_sales_product_row(product_name:, qty:, total:, cgst_pct: 9, sgst_pct: 9)
    click_button '+ Product'
    # The newly added row is the last tr in items-tbody
    within('#items-tbody tr:last-child') do
      find('.product-search-input').fill_in(with: product_name)
      within(find('.ac-dropdown', visible: true)) do
        first('div', text: product_name, wait: 5).click
      end
      find('input[name$="[quantity]"]').fill_in(with: qty.to_s)
      find('input.total-editable, input[name$="[total_amount]"]').fill_in(with: total.to_s)
    end
  end

  def save_and_confirm_sales_invoice
    click_button 'Save Invoice'
    expect(page).to have_text('Sales Invoice')
    click_button 'Confirm'
    expect(page).to have_css('.badge', text: /confirmed/i)
  end

  # ── GST Dashboard assertions ───────────────────────────────────────────

  # Assert a value appears in the tax summary card with label.
  # e.g. assert_gst_card('Output Tax', '₹3,600')
  def assert_gst_card(label, expected_value)
    within(:css, '[class*="card"], .detail-card, .stat-card', text: label) do
      expect(page).to have_text(expected_value)
    end
  end

  # Assert a row in the tax head breakdown table.
  # e.g. assert_tax_row('CGST', payable: '1,800', credit: '—')
  def assert_tax_row(head_name, values = {})
    within('table tr', text: head_name) do
      values.each_value do |val|
        expect(page).to have_text(val.to_s)
      end
    end
  end

  # ── Waiting helpers ────────────────────────────────────────────────────
  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until finished_all_ajax_requests?
    end
  end

  def finished_all_ajax_requests?
    page.evaluate_script('jQuery.active').zero?
  rescue Capybara::NotSupportedByDriverError
    true
  end

  def wait_for_turbo
    expect(page).to have_no_css('[data-turbo-progress-bar]')
  rescue Capybara::ExpectationNotMet
    true
  end
end

RSpec.configure do |config|
  config.include CapybaraHelpers, type: :feature
end
