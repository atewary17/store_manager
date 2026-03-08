# app/models/stock_level.rb
class StockLevel < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :product

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,       ->(org_id) { where(organisation_id: org_id) }
  scope :in_stock,      -> { where('quantity > 0') }
  scope :out_of_stock,  -> { where('quantity <= 0') }
  scope :ordered,       -> { joins(product: :brand).order('brands.name, products.description') }

  # ── Helpers ───────────────────────────────────────────────────
  def in_stock?
    quantity > 0
  end

  def stock_value
    return 0 if quantity <= 0 || avg_cost.nil?
    (quantity * avg_cost).round(2)
  end

end
