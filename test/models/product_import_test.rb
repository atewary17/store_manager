require "test_helper"

class ProductImportTest < ActiveSupport::TestCase
  setup do
    @import = product_imports(:recent_import)
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
    @import.status = "invalid"
    assert_not @import.valid?
  end

  test "valid statuses" do
    ProductImport::STATUSES.each do |status|
      @import.status = status
      assert @import.valid?, "#{status} should be valid"
    end
  end

  # ── Status methods ────────────────────────────────────────
  test "pending?" do
    @import.status = "pending"
    assert @import.pending?
    assert_not @import.done?
  end

  test "processing?" do
    @import.status = "processing"
    assert @import.processing?
  end

  test "done?" do
    assert @import.done?
  end

  test "failed?" do
    @import.status = "failed"
    assert @import.failed?
  end

  # ── has_errors? ────────────────────────────────────────────
  test "has_errors? with errors" do
    assert @import.has_errors? # error_count = 2
  end

  test "has_errors? without errors" do
    @import.error_count = 0
    assert_not @import.has_errors?
  end

  test "has_errors? with nil error_count" do
    @import.error_count = nil
    assert_not @import.has_errors?
  end

  # ── file_size_human ────────────────────────────────────────
  test "file_size_human in KB" do
    @import.file_size = 25600
    assert_equal "25.0 KB", @import.file_size_human
  end

  test "file_size_human in bytes" do
    @import.file_size = 500
    assert_equal "500 B", @import.file_size_human
  end

  test "file_size_human in MB" do
    @import.file_size = 2_097_152
    assert_equal "2.0 MB", @import.file_size_human
  end

  test "file_size_human with zero" do
    @import.file_size = 0
    assert_equal "—", @import.file_size_human
  end

  test "file_size_human with nil" do
    @import.file_size = nil
    assert_equal "—", @import.file_size_human
  end

  # ── Scopes ───────────────────────────────────────────────
  test "recent scope orders by created_at desc" do
    imports = ProductImport.recent
    assert_equal imports.to_a, imports.sort_by(&:created_at).reverse
  end
end
