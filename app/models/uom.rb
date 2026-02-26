# app/models/uom.rb
class Uom < ApplicationRecord
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
