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