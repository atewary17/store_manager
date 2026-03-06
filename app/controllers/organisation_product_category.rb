# app/models/organisation_product_category.rb
class OrganisationProductCategory < ApplicationRecord
  belongs_to :organisation
  belongs_to :product_category

  validates :product_category_id, uniqueness: { scope: :organisation_id,
    message: 'is already assigned to this organisation' }
end
