# spec/features/setup/product_categories_spec.rb
require 'rails_helper'

RSpec.feature "Setup Product Categories", type: :feature do
  let!(:admin) { create(:user, :super_admin) }

  before { login_as(admin, scope: :user) }

  describe "Index page" do
    let!(:cat_a) { create(:product_category, name: "Interior Paints", active: true, is_paint_type: true) }
    let!(:cat_b) { create(:product_category, name: "Hardware Items", active: true) }

    scenario "displays categories with stats" do
      visit setup_product_categories_path
      expect(page).to have_content("Product Categories")
      expect(page).to have_content("Interior Paints")
      expect(page).to have_content("Hardware Items")
      expect(page).to have_css(".stats-row")
      expect(page).to have_css(".stat-label", text: /total categories/i)
    end

    scenario "client-side search filters table", js: true do
      visit setup_product_categories_path
      fill_in "catSearch", with: "Hardware"
      expect(page).to have_content("Hardware Items")
    end

    scenario "status dropdown filters", js: true do
      visit setup_product_categories_path
      select "Active", from: "catStatusFilter"
      expect(page).to have_content("Interior Paints")
    end
  end

  describe "Creating a category" do
    scenario "creates category successfully" do
      visit setup_product_categories_path
      click_link "+ New Category"

      fill_in "Category Name *", with: "Plumbing"
      fill_in "Description", with: "Pipes and fittings"
      click_button "Create Category"

      expect(page).to have_content("Plumbing")
    end

    scenario "with paint type checkbox" do
      visit new_setup_product_category_path
      fill_in "Category Name *", with: "Exterior Paints"
      check "product_category_is_paint_type"
      click_button "Create Category"

      cat = ProductCategory.find_by(name: "Exterior Paints")
      expect(cat).to be_present
      expect(cat.is_paint_type).to be true
    end

    scenario "shows validation error for blank name" do
      visit new_setup_product_category_path
      fill_in "Category Name *", with: ""
      click_button "Create Category"

      expect(page).to have_content("error")
    end
  end

  describe "Editing a category" do
    let!(:cat) { create(:product_category, name: "Old Category") }

    scenario "updates name" do
      visit edit_setup_product_category_path(cat)
      fill_in "Category Name *", with: "Renamed Category"
      click_button "Save Changes"

      expect(page).to have_content("Renamed Category")
    end
  end
end
