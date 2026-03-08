# app/models/purchase_invoice_item.rb
class PurchaseInvoiceItem < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  belongs_to :purchase_invoice
  belongs_to :product, optional: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :matched,   -> { where(unmatched: false) }
  scope :unmatched, -> { where(unmatched: true) }

  # ── Validations ───────────────────────────────────────────────
  validates :quantity,     presence: true,
                           numericality: { greater_than: 0 }
  validates :unit_rate,    presence: true,
                           numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount, presence: true,
                           numericality: { greater_than_or_equal_to: 0 }

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :resolve_product
  before_validation :compute_total_if_blank

  # ── Helpers ───────────────────────────────────────────────────
  def product_display
    return "⚠ Unmatched — #{metadata['raw_description']}" if unmatched?
    product&.display_name || '—'
  end

  def taxable_amount
    metadata['taxable_amount'].to_f
  end

  private

  # Try to auto-match product by material_code stored in metadata
  def resolve_product
    return if product_id.present?
    raw_code = metadata['material_code'].to_s.strip
    return if raw_code.blank?

    matched = Product.find_by(
      'LOWER(TRIM(material_code)) = LOWER(TRIM(?))', raw_code
    )
    if matched
      self.product_id = matched.id
      self.unmatched  = false
    else
      self.unmatched = true
    end
  end

  def compute_total_if_blank
    return if total_amount.present? && total_amount.to_f > 0
    return unless quantity.present? && unit_rate.present?
    self.total_amount = (quantity.to_f * unit_rate.to_f).round(2)
  end

end
