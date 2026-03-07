require "test_helper"

class Setup::BrandsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @staff = users(:staff_user)
    @brand = brands(:asian_paints)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected from index" do
    sign_in @staff
    get setup_brands_path
    assert_redirected_to dashboard_path
  end

  test "unauthenticated user is redirected" do
    get setup_brands_path
    assert_response :redirect
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_brands_path
    assert_response :success
  end

  test "index renders brands" do
    sign_in @admin
    get setup_brands_path
    assert_response :success
    assert_match "Asian Paints", response.body
  end

  # ── New ────────────────────────────────────────────────────
  test "super_admin can access new" do
    sign_in @admin
    get new_setup_brand_path
    assert_response :success
  end

  # ── Create ─────────────────────────────────────────────────
  test "creates brand with valid params" do
    sign_in @admin
    assert_difference("Brand.count", 1) do
      post setup_brands_path, params: { brand: { name: "Nerolac", short_name: "NRL", active: true } }
    end
    assert_redirected_to setup_brands_path
  end

  test "does not create brand with invalid params" do
    sign_in @admin
    assert_no_difference("Brand.count") do
      post setup_brands_path, params: { brand: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  # ── Edit ───────────────────────────────────────────────────
  test "super_admin can access edit" do
    sign_in @admin
    get edit_setup_brand_path(@brand)
    assert_response :success
  end

  # ── Update ─────────────────────────────────────────────────
  test "updates brand" do
    sign_in @admin
    patch setup_brand_path(@brand), params: { brand: { name: "Asian Paints Updated" } }
    assert_redirected_to setup_brands_path
    @brand.reload
    assert_equal "Asian Paints Updated", @brand.name
  end

  # ── Destroy ────────────────────────────────────────────────
  test "destroys brand when deletable" do
    sign_in @admin
    brand = Brand.create!(name: "Deletable Brand")
    assert_difference("Brand.count", -1) do
      delete setup_brand_path(brand)
    end
    assert_redirected_to setup_brands_path
  end
end
