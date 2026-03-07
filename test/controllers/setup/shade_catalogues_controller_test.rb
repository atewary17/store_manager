require "test_helper"

class Setup::ShadeCataloguesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @shade = shade_catalogues(:red_oxide)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected" do
    sign_in users(:staff_user)
    get setup_shade_catalogues_path
    assert_redirected_to dashboard_path
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_shade_catalogues_path
    assert_response :success
  end

  test "index with category filter" do
    sign_in @admin
    get setup_shade_catalogues_path, params: { category_id: product_categories(:interior).id }
    assert_response :success
  end

  test "index with brand filter" do
    sign_in @admin
    get setup_shade_catalogues_path, params: { brand_id: brands(:asian_paints).id }
    assert_response :success
  end

  test "index with status filter" do
    sign_in @admin
    get setup_shade_catalogues_path, params: { status: "inactive" }
    assert_response :success
  end

  # ── New ────────────────────────────────────────────────────
  test "new action" do
    sign_in @admin
    get new_setup_shade_catalogue_path
    assert_response :success
  end

  # ── Create ─────────────────────────────────────────────────
  test "creates shade catalogue" do
    sign_in @admin
    assert_difference("ShadeCatalogue.count", 1) do
      post setup_shade_catalogues_path, params: {
        shade_catalogue: {
          shade_code: "GRN001",
          shade_name: "Forest Green",
          product_category_id: product_categories(:interior).id,
          brand_id: brands(:asian_paints).id,
          colour_family: "Green"
        }
      }
    end
  end

  test "invalid create" do
    sign_in @admin
    assert_no_difference("ShadeCatalogue.count") do
      post setup_shade_catalogues_path, params: {
        shade_catalogue: { shade_code: "", shade_name: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  # ── Edit ───────────────────────────────────────────────────
  test "edit action" do
    sign_in @admin
    get edit_setup_shade_catalogue_path(@shade)
    assert_response :success
  end

  # ── Update ─────────────────────────────────────────────────
  test "updates shade" do
    sign_in @admin
    patch setup_shade_catalogue_path(@shade), params: {
      shade_catalogue: { shade_name: "Updated Red" }
    }
    @shade.reload
    assert_equal "Updated Red", @shade.shade_name
  end

  # ── Destroy ────────────────────────────────────────────────
  test "destroys shade" do
    sign_in @admin
    assert_difference("ShadeCatalogue.count", -1) do
      delete setup_shade_catalogue_path(@shade)
    end
  end
end
