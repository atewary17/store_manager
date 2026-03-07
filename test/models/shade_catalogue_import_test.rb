require "test_helper"

class ShadeCatalogueImportTest < ActiveSupport::TestCase
  setup do
    @import = shade_catalogue_imports(:recent_shade_import)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid import" do
    assert @import.valid?
  end

  test "requires file_name" do
    @import.file_name = nil
    assert_not @import.valid?
  end

  test "status must be in STATUSES" do
    @import.status = "bogus"
    assert_not @import.valid?
  end

  # ── Status methods ────────────────────────────────────────
  test "pending?" do
    @import.status = "pending"
    assert @import.pending?
  end

  test "done?" do
    assert @import.done?
  end

  # ── has_errors? ────────────────────────────────────────────
  test "has_errors? with zero errors" do
    assert_not @import.has_errors? # error_count = 0
  end

  test "has_errors? with errors" do
    @import.error_count = 5
    assert @import.has_errors?
  end

  # ── file_size_human ────────────────────────────────────────
  test "file_size_human in KB" do
    @import.file_size = 15360
    assert_equal "15.0 KB", @import.file_size_human
  end

  test "file_size_human with nil" do
    @import.file_size = nil
    assert_equal "—", @import.file_size_human
  end

  # ── Associations ──────────────────────────────────────────
  test "belongs to product_category" do
    assert_respond_to @import, :product_category
    assert_equal product_categories(:interior), @import.product_category
  end

  test "belongs to user" do
    assert_equal users(:super_admin), @import.user
  end

  test "belongs to organisation" do
    assert_equal organisations(:acme), @import.organisation
  end
end
