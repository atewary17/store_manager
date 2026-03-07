# spec/features/setup/brands_spec.rb
require 'rails_helper'

RSpec.feature "Setup Brands", type: :feature do
  let!(:admin) { create(:user, :super_admin) }

  before { login_as(admin, scope: :user) }

  describe "Index page" do
    let!(:brand_a) { create(:brand, name: "Asian Paints", short_name: "AP", active: true) }
    let!(:brand_b) { create(:brand, name: "Berger Paints", short_name: "BP", active: false) }

    scenario "displays active brands by default" do
      visit setup_brands_path
      expect(page).to have_content("Brands")
      expect(page).to have_content("Asian Paints")
      expect(page).to have_content("+ New Brand")
    end

    scenario "shows stats row with totals" do
      visit setup_brands_path
      expect(page).to have_css(".stats-row")
      expect(page).to have_css(".stat-label", text: /total brands/i)
      expect(page).to have_css(".stat-label", text: /active/i)
      expect(page).to have_css(".stat-label", text: /inactive/i)
    end

    scenario "toggles between active and inactive filter" do
      visit setup_brands_path
      expect(page).to have_content("Asian Paints")

      click_link "Inactive"
      expect(page).to have_content("Berger Paints")
    end
  end

  describe "Creating a brand" do
    scenario "creates a new brand successfully" do
      visit setup_brands_path
      click_link "+ New Brand"

      fill_in "Brand Name *", with: "Nerolac"
      fill_in "Short Name / Abbreviation", with: "NRL"
      click_button "Create Brand"

      expect(page).to have_content("Nerolac")
      expect(Brand.find_by(name: "Nerolac")).to be_present
    end

    scenario "shows validation errors for blank name" do
      visit new_setup_brand_path
      fill_in "Brand Name *", with: ""
      click_button "Create Brand"

      expect(page).to have_content("error")
    end
  end

  describe "Editing a brand" do
    let!(:brand) { create(:brand, name: "Old Name") }

    scenario "updates brand name" do
      visit setup_brands_path
      click_link "Edit"

      fill_in "Brand Name *", with: "New Name"
      click_button "Update Brand"

      expect(page).to have_content("New Name")
    end
  end
end
