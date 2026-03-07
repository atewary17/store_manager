require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "super_admin can manage setup" do
    admin = users(:super_admin)
    ability = Ability.new(admin)
    assert ability.can?(:manage, :setup)
  end

  test "staff cannot manage setup" do
    staff = users(:staff_user)
    ability = Ability.new(staff)
    assert ability.cannot?(:manage, :setup)
  end

  test "guest user cannot manage setup" do
    ability = Ability.new(nil)
    assert ability.cannot?(:manage, :setup)
  end
end
