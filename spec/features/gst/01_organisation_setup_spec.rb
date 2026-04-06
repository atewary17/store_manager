# spec/features/gst/01_organisation_setup_spec.rb
#
# Feature: Organisation GST setup
# Verifies that State, State Code, GSTIN, PAN can be saved and displayed.
# This must pass before any other GST test since all supply_type logic
# depends on the organisation's state being present.

require 'rails_helper'

RSpec.describe 'Organisation GST Setup', type: :feature, js: true do
  include CapybaraHelpers

  let!(:org)   { create(:organisation, state: nil, state_code: nil) }
  let!(:admin) { create(:user, organisation: org, role: :admin,
                         email: 'admin@test.com', password: 'password123') }

  before { sign_in_as(admin) }

  scenario 'Admin fills in GST fields and verifies they are saved and displayed' do
    visit edit_organisation_path(org)

    expect(page).to have_content(/GST.*Tax Details/i)

    # Fill GST fields
    select 'West Bengal', from: 'State'
    fill_in 'State Code',  with: '19'
    fill_in 'GSTIN',       with: '19AAAAA0000A1Z5'
    fill_in 'PAN',         with: 'AAAAA0000A'
    fill_in 'organisation[address]', with: '12 Park Street, Kolkata - 700016'

    click_button 'Save'

    # Should redirect to show page with success notice
    expect(page).to have_text('updated successfully')

    # Verify all fields display on the show page
    expect(page).to have_text('West Bengal')
    expect(page).to have_text('19')
    expect(page).to have_text('19AAAAA0000A1Z5')
    expect(page).to have_text('AAAAA0000A')
    expect(page).to have_text('12 Park Street')
  end

  scenario 'Warning banner shows when State is blank' do
    visit organisation_path(org)
    # State is nil — the show view renders a warning
    expect(page).to have_text('Not set')
  end

  scenario 'Warning disappears after state is filled in' do
    visit edit_organisation_path(org)
    select 'West Bengal', from: 'State'
    fill_in 'State Code', with: '19'
    click_button 'Save'

    visit organisation_path(org)
    expect(page).to have_text('West Bengal')
    expect(page).to have_no_text('Not set — GST will default to intra-state')
  end

  scenario 'Invalid PAN format shows validation error' do
    visit edit_organisation_path(org)
    select 'West Bengal', from: 'State'
    fill_in 'PAN', with: 'INVALID123'   # wrong format
    click_button 'Save'

    expect(page).to have_text('must be 10 characters')
  end

  scenario 'Invalid State Code (letters) shows validation error' do
    visit edit_organisation_path(org)
    select 'West Bengal', from: 'State'
    fill_in 'State Code', with: 'WB'    # must be numeric
    click_button 'Save'

    expect(page).to have_text('must be 1-2 digits')
  end
end
