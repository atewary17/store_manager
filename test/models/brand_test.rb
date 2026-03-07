require "test_helper"

class BrandTest < ActiveSupport::TestCase
  setup do
    @brand = brands(:asian_paints)
  end

  # ── Validations ──────────────────────────────────────────────
  test "valid brand" do
    assert @brand.valid?
  end

  test "requires name" do
    @brand.name = nil
    assert_not @brand.valid?
    assert_includes @brand.errors[:name], "can't be blank"
  end

  test "name must be unique (case insensitive)" do
    duplicate = Brand.new(name: @brand.name.downcase)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  # ── Scopes ───────────────────────────────────────────────────
  test "active scope returns only active brands" do
    active = Brand.active
    assert active.all?(&:active?)
  end

  test "inactive scope returns only inactive brands" do
    inactive = Brand.inactive
    assert inactive.none?(&:active?)
  end

  test "ordered scope orders by name" do
    ordered = Brand.ordered
    assert_equal ordered.to_a, ordered.sort_by(&:name)
  end

  # ── Callbacks ──────────────────────────────────────────────
  test "strips whitespace from name and short_name" do
    brand = Brand.new(name: "  Test Brand  ", short_name: "  TB  ")
    brand.valid? # triggers before_save won't run on valid?, let's save
    brand.save
    assert_equal "Test Brand", brand.name
    assert_equal "TB", brand.short_name
  end

  # ── Custom methods ────────────────────────────────────────
  test "display_name with short_name" do
    assert_equal "Asian Paints (AP)", @brand.display_name
  end

  test "display_name without short_name" do
    @brand.short_name = nil
    assert_equal "Asian Paints", @brand.display_name
  end

  test "can_delete? returns true when no products or shades" do
    brand = Brand.create!(name: "Empty Brand")
    assert brand.can_delete?
  end

  test "can_delete? returns false when products exist" do
    assert_not @brand.can_delete? if @brand.products.any?
  end

  # ── Associations ──────────────────────────────────────────
  test "has many products" do
    assert_respond_to @brand, :products
  end

  test "has many shade_catalogues" do
    assert_respond_to @brand, :shade_catalogues
  end
end
