require "test_helper"

class Setup::ProductCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @category = product_categories(:interior)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected" do
    sign_in users(:staff_user)
    get setup_product_categories_path
    assert_redirected_to dashboard_path
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_product_categories_path
    assert_response :success
  end

  # ── New ────────────────────────────────────────────────────
  test "new action" do
    sign_in @admin
    get new_setup_product_category_path
    assert_response :success
  end

  # ── Create ─────────────────────────────────────────────────
  test "creates category" do
    sign_in @admin
    assert_difference("ProductCategory.count", 1) do
      post setup_product_categories_path, params: {
        product_category: { name: "Exterior", description: "Ext paints" }
      }
    end
  end

  test "invalid create" do
    sign_in @admin
    assert_no_difference("ProductCategory.count") do
      post setup_product_categories_path, params: {
        product_category: { name: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  # ── Show ───────────────────────────────────────────────────
  test "show action" do
    sign_in @admin
    get setup_product_category_path(@category)
    assert_response :success
  end

  # ── Edit ───────────────────────────────────────────────────
  test "edit action" do
    sign_in @admin
    get edit_setup_product_category_path(@category)
    assert_response :success
  end

  # ── Update ─────────────────────────────────────────────────
  test "updates category" do
    sign_in @admin
    patch setup_product_category_path(@category), params: {
      product_category: { name: "Interior Updated" }
    }
    @category.reload
    assert_equal "Interior Updated", @category.name
  end

  # ── Destroy ────────────────────────────────────────────────
  test "destroys category when deletable" do
    sign_in @admin
    cat = ProductCategory.create!(name: "Temp Cat")
    assert_difference("ProductCategory.count", -1) do
      delete setup_product_category_path(cat)
    end
  end
end
