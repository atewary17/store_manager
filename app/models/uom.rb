# app/models/uom.rb
class Uom < ApplicationRecord

  def self.cached_count
    Rails.cache.fetch('uom/count', expires_in: 10.minutes) { count }
  end

  def self.cached_active_count
    Rails.cache.fetch('uom/active_count', expires_in: 10.minutes) { where(active: true).count }
  end

  has_many :products, foreign_key: :base_uom_id, dependent: :restrict_with_error

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered,  -> { order(:name) }

  validates :name,       presence: true, uniqueness: { case_sensitive: false }
  validates :short_name, presence: true, uniqueness: { case_sensitive: false }

  # Fuzzy lookup used by UnmatchedProductCreator.
  # Priority: exact name → exact short_name → alias array → trigram similarity.
  # Returns nil when no match — caller must apply an "Others" fallback.
  def self.match_fuzzy(raw)
    return nil if raw.blank?
    n = raw.to_s.strip.downcase

    find_by('LOWER(name) = ?', n) ||
      find_by('LOWER(short_name) = ?', n) ||
      where('? = ANY(aliases)', n).first ||
      where('similarity(LOWER(name), ?) > 0.45', n).order(Arel.sql("similarity(LOWER(name), #{connection.quote(n)}) DESC")).first
  end

  def self.others
    find_by('LOWER(name) = ?', 'others') ||
      find_or_create_by!(name: 'Others') { |u| u.short_name = 'OTH'; u.active = true }
  end

  before_save :strip_whitespace

  def display
    "#{name} (#{short_name})"
  end

  def can_delete?
    products.none?
  end

  private

  def strip_whitespace
    self.name       = name.strip       if name.present?
    self.short_name = short_name.strip if short_name.present?
  end

end