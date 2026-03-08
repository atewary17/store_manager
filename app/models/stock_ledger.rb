# app/models/stock_ledger.rb
class StockLedger < ApplicationRecord

  ENTRY_TYPES = %w[opening purchase sale adjustment return].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :product
  belongs_to :user
  belongs_to :reference, polymorphic: true, optional: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,     ->(org_id)  { where(organisation_id: org_id) }
  scope :for_product, ->(prod_id) { where(product_id: prod_id) }
  scope :of_type,     ->(t)       { where(entry_type: t) }
  scope :recent,                  -> { order(created_at: :desc) }
  scope :chronological,           -> { order(created_at: :asc) }

  # ── Validations ───────────────────────────────────────────────
  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :quantity,   presence: true
  validates :quantity,   numericality: { other_than: 0 }
  validates :unit_cost,  numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # ── Callbacks ─────────────────────────────────────────────────
  # After every insert, update the cached stock_levels row
  after_create :update_stock_level

  # Ledger is append-only — never update or delete entries
  before_update { raise ActiveRecord::ReadOnlyRecord, "Stock ledger entries are immutable" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Stock ledger entries cannot be deleted" }

  # ── Display helpers ───────────────────────────────────────────
  def in?
    quantity.positive?
  end

  def out?
    quantity.negative?
  end

  def quantity_display
    in? ? "+#{quantity.to_f}" : quantity.to_f.to_s
  end

  private

  def update_stock_level
    level = StockLevel.find_or_initialize_by(
      organisation_id: organisation_id,
      product_id:      product_id
    )

    new_qty = (level.quantity || 0) + quantity

    # Recalculate weighted average cost only on stock-in entries with a cost
    if in? && unit_cost.present? && unit_cost > 0
      old_value   = (level.quantity || 0) * (level.avg_cost || 0)
      added_value = quantity * unit_cost
      new_avg     = new_qty > 0 ? (old_value + added_value) / new_qty : unit_cost
      level.avg_cost = new_avg.round(2)
    end

    level.quantity = new_qty
    level.save!
  end

end
