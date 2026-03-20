# app/models/organisation.rb
class Organisation < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :organisation_product_categories, dependent: :destroy
  has_many :product_categories, through: :organisation_product_categories

  enum subscription_plan: { basic: 'basic', pro: 'pro', enterprise: 'enterprise' }
  enum status: { active: 0, inactive: 1 }

  validates :name, presence: true
  validates :gst_number, uniqueness: true, allow_blank: true

  has_many :organisation_products, dependent: :destroy
  has_many :products, through: :organisation_products

  # All products enrolled in this org's catalogue (active only)
  def available_products
    Product.for_org(self).includes(:brand, :base_uom, :product_category)
  end
end