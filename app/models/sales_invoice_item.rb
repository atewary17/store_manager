# app/models/sales_invoice_item.rb
class SalesInvoiceItem < ApplicationRecord

  LINE_TYPES = %w[product paint adhoc].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :sales_invoice
  belongs_to :product,         optional: true
  belongs_to :shade_catalogue, optional: true
  belongs_to :base_product,    class_name: 'Product', optional: true,
                               foreign_key: :base_product_id
  belongs_to :tinter_product,  class_name: 'Product', optional: true,
                               foreign_key: :tinter_product_id

  # ── Validations ───────────────────────────────────────────────
  validates :line_type,    inclusion: { in: LINE_TYPES }
  validates :quantity,     presence: true, numericality: { greater_than: 0 }
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }

  validate :paint_item_has_shade,    if: -> { line_type == 'paint' }
  validate :product_item_has_product, if: -> { line_type == 'product' }
  validate :adhoc_item_has_description, if: -> { line_type == 'adhoc' }

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :compute_amounts

  # ── Scopes ───────────────────────────────────────────────────
  scope :paint_lines,   -> { where(line_type: 'paint') }
  scope :product_lines, -> { where(line_type: 'product') }
  scope :adhoc_lines,   -> { where(line_type: 'adhoc') }

  # ── Helpers ───────────────────────────────────────────────────
  def paint?   = line_type == 'paint'
  def product? = line_type == 'product'
  def adhoc?   = line_type == 'adhoc'

  def cgst_percent  = metadata['cgst_percent'].to_f
  def sgst_percent  = metadata['sgst_percent'].to_f
  def gst_percent   = cgst_percent + sgst_percent

  # supply_type is a proper column: 'intra_state' | 'inter_state'
  def intra_state?; supply_type == 'intra_state'; end
  def inter_state?; supply_type == 'inter_state'; end

  def shade_display
    [metadata['shade_code'], metadata['shade_name']].compact_blank.join(' — ').presence || '—'
  end

  def line_display
    case line_type
    when 'paint'   then shade_display
    when 'product' then product&.display_name || '—'
    when 'adhoc'   then description.presence || 'Ad-hoc item'
    end
  end

  private

  # User enters total_amount; we back-calculate unit_rate and taxable/tax split.
  # Also determines supply_type by comparing organisation.state vs customer.state
  # and writes the per-head GST amounts to proper columns.
  def compute_amounts
    # Always initialize NOT NULL columns so Rails never sends explicit NULL.
    self.supply_type  ||= 'intra_state'
    self.gst_rate     ||= 0
    self.cgst_amount  ||= 0
    self.sgst_amount  ||= 0
    self.igst_amount  ||= 0

    total    = total_amount.to_f
    qty      = quantity.to_f
    cgst_pct = metadata['cgst_percent'].to_f
    sgst_pct = metadata['sgst_percent'].to_f
    gst_pct  = cgst_pct + sgst_pct

    return if total <= 0 || qty <= 0

    # Back-calc: total = taxable * (1 + gst/100)
    taxable = gst_pct > 0 ? (total / (1 + gst_pct / 100.0)).round(2) : total
    tax_amt = (total - taxable).round(2)
    rate    = (taxable / qty).round(4)

    self.unit_rate      = rate
    self.taxable_amount = taxable
    self.tax_amount     = tax_amt
    self.gst_rate       = gst_pct

    # Determine supply type: compare organisation state vs customer state
    org_state      = sales_invoice&.organisation&.state.to_s.strip.downcase
    customer_state = sales_invoice&.customer&.state.to_s.strip.downcase
    is_igst        = org_state.present? && customer_state.present? &&
                     org_state != customer_state

    self.supply_type = is_igst ? 'inter_state' : 'intra_state'

    # Per-head GST amounts (proper columns + metadata kept in sync)
    if is_igst
      self.cgst_amount         = 0
      self.sgst_amount         = 0
      self.igst_amount         = tax_amt
      metadata['igst_percent'] = gst_pct
      metadata['cgst_percent'] = 0
      metadata['sgst_percent'] = 0
      metadata['igst_amount']  = tax_amt
      metadata['cgst_amount']  = 0
      metadata['sgst_amount']  = 0
    else
      computed_cgst            = (taxable * cgst_pct / 100.0).round(2)
      computed_sgst            = (taxable * sgst_pct / 100.0).round(2)
      self.cgst_amount         = computed_cgst
      self.sgst_amount         = computed_sgst
      self.igst_amount         = 0
      metadata['cgst_amount']  = computed_cgst
      metadata['sgst_amount']  = computed_sgst
      metadata['igst_amount']  = 0
    end
  end

  def paint_item_has_shade
    errors.add(:shade_catalogue, 'must be selected for paint items') if shade_catalogue_id.blank?
  end

  def product_item_has_product
    errors.add(:product, 'must be selected for product items') if product_id.blank?
  end

  def adhoc_item_has_description
    errors.add(:description, "can't be blank for ad-hoc items") if description.blank?
  end

end