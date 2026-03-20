# app/models/organisation_product.rb
class OrganisationProduct < ApplicationRecord
  belongs_to :organisation
  belongs_to :product, optional: true   # nil = org-local product with no master record

  validates :organisation_id, presence: true
  validates :product_id, uniqueness: { scope: :organisation_id,
    message: 'is already in this organisation\'s catalogue' }, allow_nil: true

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # Resolved display name — uses master product's description or local_description fallback
  def display_name
    if product
      [product.brand&.name, product.pack_code, product.description].compact_blank.join(' — ')
    else
      local_description.presence || "Unnamed product ##{id}"
    end
  end

  def effective_mrp
    mrp.presence || product&.mrp
  end
end