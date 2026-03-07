require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dashboard_path
    assert_response :redirect
  end

  test "authenticated user can access dashboard" do
    sign_in users(:super_admin)
    get dashboard_path
    assert_response :success
  end

  test "staff user can access dashboard" do
    sign_in users(:staff_user)
    get dashboard_path
    assert_response :success
  end
end
