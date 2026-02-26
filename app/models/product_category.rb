# app/models/product_category.rb
class ProductCategory < ApplicationRecord
  has_many :products, dependent: :restrict_with_error

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered,  -> { order(:name) }

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_save :strip_whitespace

  def can_delete?
    products.none?
  end

  private

  def strip_whitespace
    self.name = name.strip if name.present?
  end
end
