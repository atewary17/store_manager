require "test_helper"

class ProductCategoryTest < ActiveSupport::TestCase
  setup do
    @category = product_categories(:interior)
    @hardware = product_categories(:hardware)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid category" do
    assert @category.valid?
  end

  test "requires name" do
    @category.name = nil
    assert_not @category.valid?
  end

  test "name must be unique" do
    dup = ProductCategory.new(name: @category.name)
    assert_not dup.valid?
  end

  # ── Scopes ───────────────────────────────────────────────
  test "active scope" do
    assert ProductCategory.active.all?(&:active?)
  end

  test "paint_types scope returns only paint categories" do
    paint_types = ProductCategory.paint_types
    assert paint_types.all?(&:is_paint_type?)
    assert_includes paint_types, @category
    assert_not_includes paint_types, @hardware
  end

  test "ordered scope" do
    ordered = ProductCategory.ordered.pluck(:name)
    assert_equal ordered, ordered.sort
  end

  # ── Callbacks ──────────────────────────────────────────────
  test "strips whitespace from name" do
    cat = ProductCategory.create!(name: "  Exterior  ")
    assert_equal "Exterior", cat.name
  end

  # ── Custom methods ────────────────────────────────────────
  test "can_delete? with no products or shades" do
    cat = ProductCategory.create!(name: "Empty Cat")
    assert cat.can_delete?
  end

  test "can_delete? with products" do
    assert_not @category.can_delete? if @category.products.any?
  end

  test "import_key_display returns human label" do
    assert_equal "Material Code", @category.import_key_display
  end

  # ── Associations ──────────────────────────────────────────
  test "has many products" do
    assert_respond_to @category, :products
  end

  test "has many shade_catalogues" do
    assert_respond_to @category, :shade_catalogues
  end

  test "has many organisations through organisation_product_categories" do
    assert_respond_to @category, :organisations
  end
end
