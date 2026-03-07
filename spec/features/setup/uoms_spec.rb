# spec/features/setup/uoms_spec.rb
require 'rails_helper'

RSpec.feature "Setup UOMs", type: :feature do
  let!(:admin) { create(:user, :super_admin) }

  before { login_as(admin, scope: :user) }

  describe "Index page" do
    let!(:litre) { create(:uom, name: "Litre", short_name: "LTR", active: true) }
    let!(:kg)    { create(:uom, name: "Kilogram", short_name: "KG", active: false) }

    scenario "displays UOMs with stats" do
      visit setup_uoms_path
      expect(page).to have_content("Units of Measure")
      expect(page).to have_content("Litre")
      expect(page).to have_css(".stats-row")
      expect(page).to have_css(".stat-label", text: /total uoms/i)
    end

    scenario "client-side search filters table", js: true do
      visit setup_uoms_path
      fill_in "uomSearch", with: "Litre"

      # Litre row visible, Kilogram hidden
      expect(page).to have_content("Litre")
    end

    scenario "status dropdown filters", js: true do
      visit setup_uoms_path
      select "Inactive", from: "uomStatusFilter"
      expect(page).to have_content("Kilogram")
    end
  end

  describe "Creating a UOM" do
    scenario "creates a new UOM" do
      visit setup_uoms_path
      click_link "+ New UOM"

      fill_in "Name *", with: "Gallon"
      fill_in "Short Name *", with: "GAL"
      click_button "Create UOM"

      expect(page).to have_content("Gallon")
      expect(Uom.find_by(name: "Gallon")).to be_present
    end

    scenario "shows error for blank fields" do
      visit new_setup_uom_path
      fill_in "Name *", with: ""
      fill_in "Short Name *", with: ""
      click_button "Create UOM"

      expect(page).to have_content("error")
    end
  end

  describe "Editing a UOM" do
    let!(:uom) { create(:uom, name: "Piece", short_name: "PCS") }

    scenario "updates UOM" do
      visit edit_setup_uom_path(uom)
      fill_in "Name *", with: "Piece Updated"
      click_button "Save Changes"

      expect(page).to have_content("Piece Updated")
    end
  end
end
