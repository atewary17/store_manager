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
  # unit_rate is allowed to be 0 on creation — confirm! recalculates it
  # from total_amount / quantity. Requiring it on the API create path would
  # force callers to send a value that gets overwritten immediately.
  validates :unit_rate,    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_amount, presence: true,
                           numericality: { greater_than_or_equal_to: 0 }

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :resolve_product
  before_validation :compute_total_if_blank
  before_validation :initialize_gst_columns

  # ── Helpers ───────────────────────────────────────────────────
  def product_display
    return "⚠ Unmatched — #{metadata['raw_description']}" if unmatched?
    product&.display_name || '—'
  end

  # supply_type is now a proper column: 'intra_state' | 'inter_state'
  # Set by PurchaseInvoice#confirm! based on organisation.state vs supplier.state.

  def intra_state?
    supply_type == 'intra_state'
  end

  def inter_state?
    supply_type == 'inter_state'
  end

  # cgst_amount, sgst_amount, igst_amount are now proper decimal columns.
  # No derivation needed — read directly from the database.

  def hsn_code
    product&.hsn_code.presence || '—'
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

  # Ensure new columns that are NOT NULL default=0 are never left as nil.
  # Rails sends explicit NULL for uninitialized attributes, overriding the DB default.
  # discount_percent / discount_amount are set here on creation;
  # the real values are written by PurchaseInvoice#confirm!
  # supply_type, cgst/sgst/igst_amount default via the column default but
  # we guard them here too for safety.
  def initialize_gst_columns
    self.discount_percent ||= metadata['discount_percent'].presence&.to_f || 0
    self.discount_amount  ||= 0
    self.supply_type      ||= 'intra_state'
    self.cgst_amount      ||= 0
    self.sgst_amount      ||= 0
    self.igst_amount      ||= 0
  end

end