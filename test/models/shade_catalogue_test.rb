require "test_helper"

class ShadeCatalogueTest < ActiveSupport::TestCase
  setup do
    @shade = shade_catalogues(:red_oxide)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid shade" do
    assert @shade.valid?
  end

  test "requires shade_code" do
    @shade.shade_code = nil
    assert_not @shade.valid?
  end

  test "requires shade_name" do
    @shade.shade_name = nil
    assert_not @shade.valid?
  end

  test "requires product_category" do
    @shade.product_category = nil
    assert_not @shade.valid?
  end

  test "shade_code unique per category" do
    dup = ShadeCatalogue.new(
      shade_code: @shade.shade_code,
      shade_name: "Duplicate",
      product_category: @shade.product_category
    )
    assert_not dup.valid?
    assert_includes dup.errors[:shade_code], "already exists in this category"
  end

  test "same shade_code in different category is valid" do
    # Need another paint type category
    cat = ProductCategory.create!(name: "Exterior Paints", is_paint_type: true)
    shade = ShadeCatalogue.new(
      shade_code: @shade.shade_code,
      shade_name: "Different Cat",
      product_category: cat
    )
    assert shade.valid?
  end

  test "category must be paint type" do
    hardware = product_categories(:hardware)
    shade = ShadeCatalogue.new(
      shade_code: "HW001",
      shade_name: "Hardware shade",
      product_category: hardware
    )
    assert_not shade.valid?
    assert_includes shade.errors[:product_category], "must be a paint-type category"
  end

  # ── Scopes ───────────────────────────────────────────────
  test "active scope" do
    assert ShadeCatalogue.active.all?(&:active?)
  end

  test "inactive scope" do
    assert ShadeCatalogue.inactive.none?(&:active?)
  end

  test "for_category scope" do
    cat = product_categories(:interior)
    assert ShadeCatalogue.for_category(cat.id).all? { |s| s.product_category_id == cat.id }
  end

  test "for_brand scope" do
    brand = brands(:asian_paints)
    assert ShadeCatalogue.for_brand(brand.id).all? { |s| s.brand_id == brand.id }
  end

  test "search scope matches shade_code" do
    results = ShadeCatalogue.search("RED")
    assert_includes results, @shade
  end

  test "search scope matches shade_name" do
    results = ShadeCatalogue.search("Oxide")
    assert_includes results, @shade
  end

  # ── Callbacks ──────────────────────────────────────────────
  test "upcases shade_code on save" do
    shade = ShadeCatalogue.create!(
      shade_code: "low001",
      shade_name: "Lowercase Test",
      product_category: product_categories(:interior)
    )
    assert_equal "LOW001", shade.shade_code
  end

  test "strips whitespace" do
    @shade.shade_code = "  RED001  "
    @shade.shade_name = "  Red Oxide  "
    @shade.save!
    assert_equal "RED001", @shade.shade_code
    assert_equal "Red Oxide", @shade.shade_name
  end

  # ── Custom methods ────────────────────────────────────────
  test "display_name" do
    assert_equal "RED001 — Red Oxide", @shade.display_name
  end

  test "full_display with brand" do
    assert_includes @shade.full_display, "Asian Paints"
  end

  test "full_display without brand" do
    @shade.brand = nil
    assert_equal "RED001 — Red Oxide", @shade.full_display
  end

  test "can_delete? returns true" do
    assert @shade.can_delete?
  end
end
