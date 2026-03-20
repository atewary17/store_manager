# app/models/product.rb
class Product < ApplicationRecord

  # ── Cache helpers ─────────────────────────────────────────────
  def self.cached_count
    Rails.cache.fetch('product/count', expires_in: 10.minutes) { count }
  end

  def self.cached_active_count
    Rails.cache.fetch('product/active_count', expires_in: 10.minutes) { where(active: true).count }
  end

  # ── Associations ─────────────────────────────────────────────
  belongs_to :product_category
  belongs_to :base_uom, class_name: 'Uom', foreign_key: :base_uom_id
  belongs_to :brand, optional: true
  has_many   :organisation_products, dependent: :destroy

  # ── Scopes ───────────────────────────────────────────────────
  scope :active,          -> { where(active: true) }
  scope :inactive,        -> { where(active: false) }
  scope :ordered,         -> { joins(:brand).order('brands.name, products.description') }
  scope :for_brand,       ->(brand_id) { where(brand_id: brand_id) }
  scope :for_category,    ->(cat_id)   { where(product_category_id: cat_id) }
  scope :search,          ->(q) {
    return all if q.blank?
    term = "%#{q.downcase}%"
    left_joins(:brand).where(
      'LOWER(brands.name) LIKE ? OR LOWER(products.description) LIKE ? OR LOWER(products.material_code) LIKE ? OR LOWER(products.product_code) LIKE ?',
      term, term, term, term
    )
  }

  # ── Org-scoped scope ─────────────────────────────────────────
  # Returns only products that have been enrolled in the given org's catalogue.
  # All product lookups in org-facing features must go through this scope.
  scope :for_org, ->(org_or_id) {
    org_id = org_or_id.is_a?(Organisation) ? org_or_id.id : org_or_id.to_i
    joins(:organisation_products)
      .where(organisation_products: { organisation_id: org_id, active: true })
  }

  # Enrol this product in an org's catalogue (idempotent)
  def enrol_in!(org_or_id)
    org_id = org_or_id.is_a?(Organisation) ? org_or_id.id : org_or_id.to_i
    OrganisationProduct.find_or_create_by!(organisation_id: org_id, product_id: id)
  end

  # ── Constants ─────────────────────────────────────────────────
  GST_RATES = [0.0, 5.0, 12.0, 18.0, 28.0].freeze

  # ── Validations ───────────────────────────────────────────────
  validates :brand,            presence: true
  validates :description,      presence: true
  validates :gst_rate,         inclusion: { in: GST_RATES,
                                 message: "must be one of: #{GST_RATES.join(', ')}%" }
  validates :product_category, presence: true
  validates :base_uom,         presence: true
  validates :material_code,    uniqueness: true, allow_blank: true
  validates :product_code,     uniqueness: true, allow_blank: true
  validates :mrp,              numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace
  before_save :nullify_blank_codes

  # ── Display helpers ───────────────────────────────────────────
  def display_name
    parts = [brand&.name, pack_code, description].compact_blank
    parts.join(' — ')
  end

  def full_code
    [material_code, product_code].compact_blank.join(' / ')
  end

  private

  def strip_whitespace
    %i[material_code product_code pack_code hsn_code].each do |field|
      self[field] = self[field].strip if self[field].present?
    end
  end

  def nullify_blank_codes
    self.material_code = nil if material_code.blank?
    self.product_code  = nil if product_code.blank?
  end

end