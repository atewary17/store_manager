require "test_helper"

class Setup::ProductImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:super_admin)
  end

  # ── Authorization ──────────────────────────────────────────
  test "staff user is redirected" do
    sign_in users(:staff_user)
    get setup_product_imports_path
    assert_redirected_to dashboard_path
  end

  # ── Index ──────────────────────────────────────────────────
  test "super_admin can access index" do
    sign_in @admin
    get setup_product_imports_path
    assert_response :success
  end

  # ── New ────────────────────────────────────────────────────
  test "new import form" do
    sign_in @admin
    get new_setup_product_import_path
    assert_response :success
  end
end
