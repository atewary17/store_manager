# spec/features/setup/authorization_spec.rb
require 'rails_helper'

RSpec.feature "Setup Authorization", type: :feature do
  describe "non-super_admin access" do
    let!(:staff) { create(:user, role: :staff) }

    scenario "staff user is redirected from brands" do
      login_as(staff, scope: :user)
      visit setup_brands_path
      expect(page).to have_content("Access denied")
    end

    scenario "staff user is redirected from products" do
      login_as(staff, scope: :user)
      visit setup_products_path
      expect(page).to have_content("Access denied")
    end

    scenario "staff user is redirected from shade catalogues" do
      login_as(staff, scope: :user)
      visit setup_shade_catalogues_path
      expect(page).to have_content("Access denied")
    end
  end

  describe "super_admin access" do
    let!(:admin) { create(:user, :super_admin) }

    scenario "can access all setup pages" do
      login_as(admin, scope: :user)

      visit setup_brands_path
      expect(page).to have_content("Brands")

      visit setup_uoms_path
      expect(page).to have_content("Units of Measure")

      visit setup_product_categories_path
      expect(page).to have_content("Product Categories")

      visit setup_products_path
      expect(page).to have_content("Products")

      visit setup_shade_catalogues_path
      expect(page).to have_content("Shade Catalogue")

      visit setup_product_imports_path
      expect(page).to have_content("Imports")
    end
  end
end
