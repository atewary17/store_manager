# spec/features/setup/products_spec.rb
require 'rails_helper'

RSpec.feature "Setup Products", type: :feature do
  let!(:admin)    { create(:user, :super_admin) }
  let!(:brand)    { create(:brand, name: "Asian Paints") }
  let!(:category) { create(:product_category, name: "Interior", active: true) }
  let!(:uom)      { create(:uom, name: "Litre", short_name: "LTR") }

  before { login_as(admin, scope: :user) }

  describe "Index page" do
    let!(:product_a) { create(:product, brand: brand, product_category: category, base_uom: uom,
                              description: "Royale Lustre 10L", material_code: "MAT_A") }
    let!(:product_b) { create(:product, brand: brand, product_category: category, base_uom: uom,
                              description: "Tractor Emulsion 20L", material_code: "MAT_B", active: false) }

    scenario "displays products with stats" do
      visit setup_products_path
      expect(page).to have_content("Products")
      expect(page).to have_content("Royale Lustre 10L")
      expect(page).to have_css(".stats-row")
      expect(page).to have_css(".stat-label", text: /total products/i)
      expect(page).to have_content("+ New Product")
      expect(page).to have_content("Export Excel")
    end

    scenario "filters by category" do
      visit setup_products_path
      select "Interior", from: "category_id"
      click_button "Filter"
      expect(page).to have_content("Royale Lustre 10L")
    end

    scenario "filters by brand" do
      visit setup_products_path
      select "Asian Paints", from: "brand_id"
      click_button "Filter"
      expect(page).to have_content("Royale Lustre 10L")
    end

    scenario "filters by status" do
      visit setup_products_path
      select "Inactive", from: "status"
      click_button "Filter"
      expect(page).to have_content("Tractor Emulsion 20L")
    end

    scenario "clears filters" do
      visit setup_products_path(status: "inactive")
      click_link "Clear"
      expect(page).to have_current_path(setup_products_path)
    end

    scenario "client-side search filters table", js: true do
      visit setup_products_path
      fill_in "productSearch", with: "Royale"
      expect(page).to have_content("Royale Lustre 10L")
    end
  end

  describe "Creating a product" do
    scenario "creates product with all fields" do
      visit setup_products_path
      click_link "+ New Product"

      select "Interior", from: "product[product_category_id]"
      select "Litre (LTR)", from: "product[base_uom_id]"
      select "Asian Paints", from: "product[brand_id]"
      fill_in "Description *", with: "Apex Weathercoat 4L"
      fill_in "Material Code", with: "MATTEST001"
      fill_in "HSN Code", with: "32091000"
      select "18% — Standard goods", from: "product[gst_rate]"
      click_button "Create Product"

      expect(Product.find_by(description: "Apex Weathercoat 4L")).to be_present
    end

    scenario "shows validation errors" do
      visit new_setup_product_path
      click_button "Create Product"
      expect(page).to have_content("error")
    end
  end

  describe "Editing a product" do
    let!(:product) { create(:product, brand: brand, product_category: category, base_uom: uom,
                            description: "Old Description", material_code: "MATEDIT") }

    scenario "updates product description" do
      visit edit_setup_product_path(product)
      fill_in "Description *", with: "Updated Description"
      click_button "Save Changes"

      product.reload
      expect(product.description).to eq("Updated Description")
    end
  end
end
