# app/models/brand.rb
class Brand < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  has_many :products,         dependent: :restrict_with_error
  has_many :shade_catalogues, dependent: :restrict_with_error

  # ── Scopes ───────────────────────────────────────────────────
  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered,  -> { order(:name) }

  # ── Validations ───────────────────────────────────────────────
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace

  # ── Cache helpers ─────────────────────────────────────────────
  def self.cached_count
    Rails.cache.fetch('brand/count', expires_in: 10.minutes) { count }
  end

  def self.cached_active_count
    Rails.cache.fetch('brand/active_count', expires_in: 10.minutes) { where(active: true).count }
  end

  # ── Display ───────────────────────────────────────────────────
  def display_name
    short_name.present? ? "#{name} (#{short_name})" : name
  end

  def can_delete?
    products.none? && shade_catalogues.none?
  end

  private

  def strip_whitespace
    self.name       = name.strip       if name.present?
    self.short_name = short_name.strip if short_name.present?
  end

end
