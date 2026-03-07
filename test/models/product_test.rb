require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup do
    @product = products(:royale_lustre)
  end

  # ── Validations ──────────────────────────────────────────
  test "valid product" do
    assert @product.valid?
  end

  test "requires brand" do
    @product.brand = nil
    assert_not @product.valid?
  end

  test "requires description" do
    @product.description = nil
    assert_not @product.valid?
  end

  test "requires product_category" do
    @product.product_category = nil
    assert_not @product.valid?
  end

  test "requires base_uom" do
    @product.base_uom = nil
    assert_not @product.valid?
  end

  test "gst_rate must be valid" do
    @product.gst_rate = 15.0
    assert_not @product.valid?
    assert_includes @product.errors[:gst_rate], "must be one of: 0.0, 5.0, 12.0, 18.0, 28.0%"
  end

  test "valid gst_rates accepted" do
    Product::GST_RATES.each do |rate|
      @product.gst_rate = rate
      assert @product.valid?, "GST rate #{rate} should be valid"
    end
  end

  test "material_code uniqueness" do
    other = products(:weather_coat)
    other.material_code = @product.material_code
    assert_not other.valid?
  end

  test "product_code uniqueness" do
    other = products(:weather_coat)
    other.product_code = @product.product_code
    assert_not other.valid?
  end

  test "mrp must be non-negative" do
    @product.mrp = -1
    assert_not @product.valid?
  end

  # ── Scopes ───────────────────────────────────────────────
  test "active scope" do
    assert Product.active.all?(&:active?)
  end

  test "inactive scope" do
    assert Product.inactive.none?(&:active?)
  end

  test "for_category scope" do
    cat = product_categories(:interior)
    scoped = Product.for_category(cat.id)
    assert scoped.all? { |p| p.product_category_id == cat.id }
  end

  test "for_brand scope" do
    brand = brands(:asian_paints)
    scoped = Product.for_brand(brand.id)
    assert scoped.all? { |p| p.brand_id == brand.id }
  end

  test "search scope matches description" do
    results = Product.search("Royale")
    assert_includes results, @product
  end

  test "search scope with blank returns all" do
    assert_equal Product.all.count, Product.search("").count
  end

  # ── Callbacks ──────────────────────────────────────────────
  test "strips whitespace from codes" do
    @product.material_code = "  MAT001  "
    @product.save!
    assert_equal "MAT001", @product.material_code
  end

  test "nullifies blank codes" do
    @product.material_code = ""
    @product.product_code = ""
    @product.save!
    assert_nil @product.material_code
    assert_nil @product.product_code
  end

  # ── Custom methods ────────────────────────────────────────
  test "display_name combines brand, pack_code, description" do
    assert_includes @product.display_name, "Asian Paints"
    assert_includes @product.display_name, "Royale Lustre 10L"
  end

  test "full_code combines material and product codes" do
    assert_equal "MAT001 / PRD001", @product.full_code
  end

  test "full_code with blank codes" do
    @product.material_code = nil
    @product.product_code = nil
    assert_equal "", @product.full_code
  end
end
