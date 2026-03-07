require "test_helper"

class UomTest < ActiveSupport::TestCase
  setup do
    @uom = uoms(:litre)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid uom" do
    assert @uom.valid?
  end

  test "requires name" do
    @uom.name = nil
    assert_not @uom.valid?
  end

  test "requires short_name" do
    @uom.short_name = nil
    assert_not @uom.valid?
  end

  test "name must be unique (case insensitive)" do
    dup = Uom.new(name: @uom.name.downcase, short_name: "XX")
    assert_not dup.valid?
  end

  test "short_name must be unique (case insensitive)" do
    dup = Uom.new(name: "Unique Name", short_name: @uom.short_name.downcase)
    assert_not dup.valid?
  end

  # ── Scopes ───────────────────────────────────────────────
  test "active scope" do
    assert Uom.active.all?(&:active?)
  end

  test "inactive scope" do
    assert Uom.inactive.none?(&:active?)
  end

  test "ordered scope" do
    ordered = Uom.ordered.pluck(:name)
    assert_equal ordered, ordered.sort
  end

  # ── Callbacks ──────────────────────────────────────────────
  test "strips whitespace" do
    uom = Uom.create!(name: "  Gallon  ", short_name: "  GAL  ")
    assert_equal "Gallon", uom.name
    assert_equal "GAL", uom.short_name
  end

  # ── Custom methods ────────────────────────────────────────
  test "display method" do
    assert_equal "Litre (LTR)", @uom.display
  end

  test "can_delete? when no products use it" do
    uom = Uom.create!(name: "Piece", short_name: "PC")
    assert uom.can_delete?
  end

  test "can_delete? returns false when products use it" do
    # litre has products via fixtures
    assert_not @uom.can_delete? if @uom.products.any?
  end
end
