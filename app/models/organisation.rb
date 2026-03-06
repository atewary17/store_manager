# app/models/organisation.rb
class Organisation < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :organisation_product_categories, dependent: :destroy
  has_many :product_categories, through: :organisation_product_categories

  enum subscription_plan: { basic: 'basic', pro: 'pro', enterprise: 'enterprise' }
  enum status: { active: 0, inactive: 1 }

  validates :name, presence: true
  validates :gst_number, uniqueness: true, allow_blank: true

  # Products visible to this organisation (scoped through assigned categories)
  def available_products
    Product.joins(:product_category)
           .where(product_category_id: product_categories.select(:id))
           .active
  end
end