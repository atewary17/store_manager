require "test_helper"

class Setup::ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @product = products(:royale_lustre)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected" do
    sign_in users(:staff_user)
    get setup_products_path
    assert_redirected_to dashboard_path
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_products_path
    assert_response :success
  end

  test "index with category filter" do
    sign_in @admin
    get setup_products_path, params: { category_id: product_categories(:interior).id }
    assert_response :success
  end

  test "index with brand filter" do
    sign_in @admin
    get setup_products_path, params: { brand_id: brands(:asian_paints).id }
    assert_response :success
  end

  test "index with status filter" do
    sign_in @admin
    get setup_products_path, params: { status: "active" }
    assert_response :success
  end

  # ── New ────────────────────────────────────────────────────
  test "new action" do
    sign_in @admin
    get new_setup_product_path
    assert_response :success
  end

  # ── Create ─────────────────────────────────────────────────
  test "creates product" do
    sign_in @admin
    assert_difference("Product.count", 1) do
      post setup_products_path, params: {
        product: {
          product_category_id: product_categories(:interior).id,
          base_uom_id: uoms(:litre).id,
          brand_id: brands(:asian_paints).id,
          description: "New Test Product",
          gst_rate: 18.0,
          material_code: "NEWMAT001"
        }
      }
    end
  end

  test "invalid create" do
    sign_in @admin
    assert_no_difference("Product.count") do
      post setup_products_path, params: {
        product: { description: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  # ── Show ───────────────────────────────────────────────────
  test "show action" do
    sign_in @admin
    get setup_product_path(@product)
    assert_response :success
  end

  # ── Edit ───────────────────────────────────────────────────
  test "edit action" do
    sign_in @admin
    get edit_setup_product_path(@product)
    assert_response :success
  end

  # ── Update ─────────────────────────────────────────────────
  test "updates product" do
    sign_in @admin
    patch setup_product_path(@product), params: {
      product: { description: "Updated Description" }
    }
    @product.reload
    assert_equal "Updated Description", @product.description
  end

  # ── Destroy ────────────────────────────────────────────────
  test "destroys product" do
    sign_in @admin
    assert_difference("Product.count", -1) do
      delete setup_product_path(@product)
    end
  end

  # ── Export ─────────────────────────────────────────────────
  test "export as xlsx" do
    sign_in @admin
    get export_setup_products_path(format: :xlsx)
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                 response.content_type.split(";").first
  end
end
