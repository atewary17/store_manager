# app/models/shade_catalogue.rb
class ShadeCatalogue < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  belongs_to :product_category
  belongs_to :brand, optional: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :active,       -> { where(active: true) }
  scope :inactive,     -> { where(active: false) }
  scope :ordered,      -> { order(:shade_code) }
  scope :for_category, ->(cat_id) { where(product_category_id: cat_id) }
  scope :for_brand,    ->(brand_id) { where(brand_id: brand_id) }
  scope :search, ->(q) {
    return all if q.blank?
    term = "%#{q.downcase}%"
    left_joins(:brand).where(
      'LOWER(shade_catalogues.shade_code) LIKE ? OR LOWER(shade_catalogues.shade_name) LIKE ? OR LOWER(brands.name) LIKE ? OR LOWER(shade_catalogues.colour_family) LIKE ?',
      term, term, term, term
    )
  }

  # ── Validations ───────────────────────────────────────────────
  validates :shade_code,       presence: true
  validates :shade_name,       presence: true
  validates :product_category, presence: true
  validates :shade_code,
            uniqueness: { scope: :product_category_id,
                          message: 'already exists in this category',
                          case_sensitive: false }

  validate :category_must_be_paint_type

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace
  before_save :upcase_shade_code

  # ── Cache helpers ─────────────────────────────────────────────
  def self.cached_count
    Rails.cache.fetch('shade_catalogue/count', expires_in: 10.minutes) { count }
  end

  def self.cached_active_count
    Rails.cache.fetch('shade_catalogue/active_count', expires_in: 10.minutes) { where(active: true).count }
  end

  # ── Display helpers ───────────────────────────────────────────
  def display_name
    "#{shade_code} — #{shade_name}"
  end

  def full_display
    parts = [shade_code, shade_name]
    parts << "(#{brand.name})" if brand.present?
    parts.join(' — ')
  end

  def can_delete?
    true # will check sales_invoice_items once that table exists
  end

  private

  def strip_whitespace
    self.shade_code     = shade_code.strip     if shade_code.present?
    self.shade_name     = shade_name.strip     if shade_name.present?
    self.colour_family  = colour_family.strip  if colour_family.present?
    self.product_family = product_family.strip if product_family.present?
  end

  def upcase_shade_code
    self.shade_code = shade_code.upcase if shade_code.present?
  end

  def category_must_be_paint_type
    return unless product_category
    return if product_category.is_paint_type?
    errors.add(:product_category, 'must be a paint-type category')
  end

end
