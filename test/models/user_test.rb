require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @admin = users(:super_admin)
    @staff = users(:staff_user)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid user" do
    assert @admin.valid?
  end

  test "requires email" do
    @admin.email = nil
    assert_not @admin.valid?
  end

  test "email must be unique" do
    dup = User.new(email: @admin.email, password: "password123", role: :staff)
    assert_not dup.valid?
  end

  test "requires role" do
    @admin.role = nil
    assert_not @admin.valid?
  end

  # ── Roles ────────────────────────────────────────────────
  test "role enum values" do
    assert_equal 0, User.roles[:staff]
    assert_equal 1, User.roles[:admin]
    assert_equal 2, User.roles[:owner]
    assert_equal 3, User.roles[:super_admin]
  end

  test "super_admin?" do
    assert @admin.super_admin?
    assert_not @staff.super_admin?
  end

  # ── Status ───────────────────────────────────────────────
  test "status enum" do
    assert @admin.active?
  end

  test "active scope" do
    assert User.active.all?(&:active?)
  end

  # ── Display helpers ──────────────────────────────────────
  test "full_name with first and last name" do
    assert_equal "Super Admin", @admin.full_name
  end

  test "full_name falls back to email prefix" do
    @admin.first_name = nil
    @admin.last_name = nil
    assert_equal "admin", @admin.full_name
  end

  test "initials with names" do
    assert_equal "SA", @admin.initials
  end

  test "initials falls back to email first char" do
    @admin.first_name = nil
    @admin.last_name = nil
    assert_equal "A", @admin.initials
  end

  # ── Associations ──────────────────────────────────────────
  test "belongs to organisation" do
    assert_respond_to @admin, :organisation
    assert_equal organisations(:acme), @admin.organisation
  end
end
