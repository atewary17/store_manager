require "test_helper"

class Setup::UomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
    @staff = users(:staff_user)
    @uom = uoms(:litre)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected" do
    sign_in @staff
    get setup_uoms_path
    assert_redirected_to dashboard_path
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_uoms_path
    assert_response :success
  end

  # ── New ────────────────────────────────────────────────────
  test "super_admin can access new" do
    sign_in @admin
    get new_setup_uom_path
    assert_response :success
  end

  # ── Create ─────────────────────────────────────────────────
  test "creates uom with valid params" do
    sign_in @admin
    assert_difference("Uom.count", 1) do
      post setup_uoms_path, params: { uom: { name: "Gallon", short_name: "GAL" } }
    end
  end

  test "does not create uom with invalid params" do
    sign_in @admin
    assert_no_difference("Uom.count") do
      post setup_uoms_path, params: { uom: { name: "", short_name: "" } }
    end
    assert_response :unprocessable_entity
  end

  # ── Show ───────────────────────────────────────────────────
  test "super_admin can access show" do
    sign_in @admin
    get setup_uom_path(@uom)
    assert_response :success
  end

  # ── Edit ───────────────────────────────────────────────────
  test "super_admin can access edit" do
    sign_in @admin
    get edit_setup_uom_path(@uom)
    assert_response :success
  end

  # ── Update ─────────────────────────────────────────────────
  test "updates uom" do
    sign_in @admin
    patch setup_uom_path(@uom), params: { uom: { name: "Litre Updated" } }
    @uom.reload
    assert_equal "Litre Updated", @uom.name
  end

  # ── Destroy ────────────────────────────────────────────────
  test "destroys uom when deletable" do
    sign_in @admin
    uom = Uom.create!(name: "Deletable", short_name: "DEL")
    assert_difference("Uom.count", -1) do
      delete setup_uom_path(uom)
    end
  end
end
