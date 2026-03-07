# spec/features/setup/shade_catalogues_spec.rb
require 'rails_helper'

RSpec.feature "Setup Shade Catalogues", type: :feature do
  let!(:admin)  { create(:user, :super_admin) }
  let!(:brand)  { create(:brand, name: "Asian Paints") }
  let!(:paint_cat) { create(:product_category, :paint_type, name: "Interior Emulsions") }

  before { login_as(admin, scope: :user) }

  describe "Index page" do
    let!(:shade_a) { create(:shade_catalogue, shade_code: "RED001", shade_name: "Ruby Red",
                            product_category: paint_cat, brand: brand, colour_family: "Red") }
    let!(:shade_b) { create(:shade_catalogue, shade_code: "BLU001", shade_name: "Sky Blue",
                            product_category: paint_cat, brand: brand, colour_family: "Blue", active: false) }

    scenario "displays shades with stats" do
      visit setup_shade_catalogues_path
      expect(page).to have_content("Shade Catalogue")
      expect(page).to have_content("RED001")
      expect(page).to have_content("Ruby Red")
      expect(page).to have_css(".stats-row")
      expect(page).to have_css(".stat-label", text: /total shades/i)
      expect(page).to have_content("Export Excel")
      expect(page).to have_content("+ New Shade")
    end

    scenario "filters by category" do
      visit setup_shade_catalogues_path
      select "Interior Emulsions", from: "category_id"
      click_button "Filter"
      expect(page).to have_content("RED001")
    end

    scenario "filters by brand" do
      visit setup_shade_catalogues_path
      select "Asian Paints", from: "brand_id"
      click_button "Filter"
      expect(page).to have_content("RED001")
    end

    scenario "filters inactive shades" do
      visit setup_shade_catalogues_path
      select "Inactive", from: "status"
      click_button "Filter"
      expect(page).to have_content("BLU001")
      expect(page).to have_content("Sky Blue")
    end

    scenario "clears filters" do
      visit setup_shade_catalogues_path(status: "inactive")
      click_link "Clear"
      expect(page).to have_current_path(setup_shade_catalogues_path)
    end

    scenario "client-side search filters table", js: true do
      visit setup_shade_catalogues_path
      fill_in "shadeSearch", with: "Ruby"
      expect(page).to have_content("Ruby Red")
    end
  end

  describe "Creating a shade" do
    scenario "creates shade with all fields" do
      visit setup_shade_catalogues_path
      click_link "+ New Shade"

      select "Interior Emulsions", from: "shade_catalogue_product_category_id"
      select "Asian Paints", from: "shade_catalogue_brand_id"
      fill_in "Shade Code *", with: "GRN001"
      fill_in "Shade Name *", with: "Forest Green"
      fill_in "Colour Family", with: "Green"
      fill_in "Notes", with: "Interior use only"
      click_button "Add Shade"

      expect(ShadeCatalogue.find_by(shade_code: "GRN001")).to be_present
    end

    scenario "shows validation errors for missing fields" do
      visit new_setup_shade_catalogue_path
      fill_in "Shade Code *", with: ""
      fill_in "Shade Name *", with: ""
      click_button "Add Shade"
      expect(page).to have_content("error")
    end
  end

  describe "Editing a shade" do
    let!(:shade) { create(:shade_catalogue, shade_code: "YLW001", shade_name: "Lemon Yellow",
                          product_category: paint_cat, brand: brand) }

    scenario "updates shade name" do
      visit edit_setup_shade_catalogue_path(shade)
      fill_in "Shade Name *", with: "Golden Yellow"
      click_button "Update Shade"

      # Wait for redirect to complete before checking DB
      expect(page).to have_content("Golden Yellow")
      shade.reload
      expect(shade.shade_name).to eq("Golden Yellow")
    end
  end
end
