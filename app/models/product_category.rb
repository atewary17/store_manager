# app/models/product_category.rb
class ProductCategory < ApplicationRecord

  def self.cached_count
    Rails.cache.fetch('product_category/count', expires_in: 10.minutes) { count }
  end

  def self.cached_active_count
    Rails.cache.fetch('product_category/active_count', expires_in: 10.minutes) { where(active: true).count }
  end

  # ── Associations ─────────────────────────────────────────────
  has_many :products,                        dependent: :restrict_with_error
  has_many :shade_catalogues,                dependent: :restrict_with_error
  has_many :organisation_product_categories, dependent: :destroy
  has_many :organisations,                   through: :organisation_product_categories

  # ── Scopes ───────────────────────────────────────────────────
  scope :active,      -> { where(active: true) }
  scope :inactive,    -> { where(active: false) }
  scope :ordered,     -> { order(:name) }
  scope :paint_types, -> { where(is_paint_type: true) }

  # ── Validations ───────────────────────────────────────────────
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # ── Constants ─────────────────────────────────────────────────
  IMPORT_KEY_OPTIONS = {
    'material_code' => 'Material Code',
    'product_code'  => 'Product Code',
    'pack_code'     => 'Pack Code',
    'hsn_code'      => 'HSN Code'
  }.freeze

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace
  before_save :sync_import_key_label, if: :import_key_column_exists?

  # ── Display helpers ───────────────────────────────────────────
  def import_key_display
    return 'Material Code' unless import_key_column_exists?
    key = self[:import_key].presence || 'material_code'
    IMPORT_KEY_OPTIONS[key] || key.humanize
  end

  def can_delete?
    products.none? && shade_catalogues.none?
  end

  private

  def import_key_column_exists?
    self.class.column_names.include?('import_key')
  end

  def sync_import_key_label
    return unless self.class.column_names.include?('import_key_label')
    self.import_key_label = IMPORT_KEY_OPTIONS[import_key] if import_key.present?
  end

  def strip_whitespace
    self.name = name.strip if name.present?
  end

end