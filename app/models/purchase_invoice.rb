# app/models/purchase_invoice.rb
class PurchaseInvoice < ApplicationRecord

  STATUSES = %w[draft confirmed].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :supplier,     optional: true
  belongs_to :user
  has_many   :purchase_invoice_items, dependent: :destroy
  has_many   :purchase_payments,       dependent: :destroy

  accepts_nested_attributes_for :purchase_invoice_items,
    reject_if: ->(attrs) { attrs[:quantity].blank? && attrs[:total_amount].blank? },
    allow_destroy: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :draft,     -> { where(status: 'draft') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :recent,    -> { order(created_at: :desc) }
  scope :for_org,   ->(org_id) { where(organisation_id: org_id) }

  # ── Validations ───────────────────────────────────────────────
  validates :status, inclusion: { in: STATUSES }
  validates :delivery_date, presence: true
  validate  :cannot_edit_if_confirmed

  # ── Confirm ───────────────────────────────────────────────────
  def confirm!(current_user)
    if confirmed?
      errors.add(:base, 'Already confirmed')
      return false
    end

    ActiveRecord::Base.transaction do
      # Compute totals from items
      # Recompute unit_rate = total_amount / quantity for each item
      purchase_invoice_items.each do |item|
        qty   = item.quantity.to_f
        total = item.total_amount.to_f
        item.unit_rate = (qty > 0 && total > 0) ? (total / qty).round(4) : 0

        # ── GST: use new gst_rate column (from product), fall back to old metadata keys ──
        # New form saves gst_rate via gst-rate-input hidden field in metadata temporarily;
        # prefer product.gst_rate as the authoritative source.
        rate = item.product&.gst_rate.to_f
        rate = item.metadata['gst_rate'].to_f        if rate.zero? && item.metadata['gst_rate'].present?
        rate = (item.metadata['cgst_percent'].to_f +
                item.metadata['sgst_percent'].to_f +
                item.metadata['igst_percent'].to_f)   if rate.zero?

        disc_pct  = item.metadata['discount_percent'].to_f
        taxable   = rate > 0 ? (total / (1 + rate / 100.0)).round(2) : total
        tax_amt   = (total - taxable).round(2)

        # Intra-state split (CGST + SGST) vs inter-state (IGST)
        # Determined by comparing organisation state with supplier state.
        # Defaults to intra-state (CGST+SGST) if states unavailable.
        is_igst   = self.supplier&.state.present? &&
                    self.organisation&.state.present? &&
                    self.supplier.state.strip.downcase !=
                      self.organisation.state.strip.downcase

        cgst_pct  = is_igst ? 0 : (rate / 2.0).round(2)
        sgst_pct  = is_igst ? 0 : (rate / 2.0).round(2)
        igst_pct  = is_igst ? rate : 0

        # ── Compute per-head GST amounts ─────────────────────────────────────
        computed_cgst = is_igst ? 0 : (taxable * cgst_pct / 100.0).round(2)
        computed_sgst = is_igst ? 0 : (taxable * sgst_pct / 100.0).round(2)
        computed_igst = is_igst ? (taxable * igst_pct / 100.0).round(2) : 0
        supply        = is_igst ? 'inter_state' : 'intra_state'

        # ── Write proper decimal columns (source of truth) ────────────────
        item.gst_rate        = rate
        item.taxable_amount  = taxable
        item.tax_amount      = tax_amt
        item.discount_percent = disc_pct
        item.discount_amount  = disc_pct > 0 ?
          ((taxable / (1 - disc_pct / 100.0)) * (disc_pct / 100.0)).round(2) : 0
        item.supply_type     = supply
        item.cgst_amount     = computed_cgst
        item.sgst_amount     = computed_sgst
        item.igst_amount     = computed_igst

        # ── Keep metadata in sync for backward compat ────────────────────
        item.metadata = item.metadata.merge(
          'gst_rate'       => rate,
          'taxable_amount' => taxable,
          'cgst_percent'   => cgst_pct,
          'sgst_percent'   => sgst_pct,
          'igst_percent'   => igst_pct,
          'cgst_amount'    => computed_cgst,
          'sgst_amount'    => computed_sgst,
          'igst_amount'    => computed_igst,
          'supply_type'    => supply
        )
        item.save!
      end

      # Aggregate totals from new proper columns
      self.total_taxable_amount = purchase_invoice_items.sum(&:taxable_amount)
      self.total_tax_amount     = purchase_invoice_items.sum(&:tax_amount)
      self.total_amount         = purchase_invoice_items.sum(&:total_amount)
      self.status           = 'confirmed'
      self.confirmed_at     = Time.current
      save!

      # Create stock ledger entries for ALL items that have a product_id —
      # including AI-enriched pending products (active: false, source: ai_enrichment).
      # Stock must be tracked regardless of product active status.
      # Only sales invoice search excludes inactive products — purchasing and stock do not.
      #
      # Items with no product_id at all (truly unmatched, no product record created)
      # are skipped — there is nothing to track stock against.
      purchase_invoice_items
        .select { |i| i.product_id.present? }
        .each do |item|
          StockLedger.create!(
            organisation:   organisation,
            product_id:     item.product_id,
            user:           current_user,
            entry_type:     'purchase',
            quantity:       item.quantity,
            unit_cost:      item.unit_rate,
            notes:          "Purchase Invoice #{invoice_number.presence || id}"                             "#{item.unmatched? ? ' [pending product — awaiting admin review]' : ''}",
            reference_type: 'PurchaseInvoice',
            reference_id:   id
          )
        end
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  # ── Helpers ───────────────────────────────────────────────────
  def draft?
    status == 'draft'
  end

  def confirmed?
    status == 'confirmed'
  end

  def unmatched_count
    purchase_invoice_items.where(unmatched: true).count
  end

  def display_number
    invoice_number.presence || "Draft ##{id}"
  end

  # ── Payment helpers ─────────────────────────────────────────
  def total_paid
    purchase_payments.sum(:amount).to_f.round(2)
  end

  def outstanding_amount
    (total_amount.to_f - total_paid).round(2)
  end

  def fully_paid?
    outstanding_amount <= 0
  end

  def overdue?
    payment_due_date.present? && payment_due_date < Date.today && !fully_paid?
  end

  def payment_status
    if fully_paid?
      'paid'
    elsif total_paid > 0
      'partial'
    else
      'unpaid'
    end
  end

  private

  # Fields that confirm! is allowed to write on a confirmed record
  CONFIRM_FIELDS = %w[status confirmed_at total_taxable_amount total_tax_amount total_amount payment_due_date].freeze

  def cannot_edit_if_confirmed
    return unless confirmed?
    return unless changed?
    # Allow the transition itself (draft → confirmed) and the aggregate fields confirm! sets
    illegal = changes.keys - CONFIRM_FIELDS
    if illegal.any?
      errors.add(:base, 'Confirmed invoices cannot be edited')
    end
  end

end