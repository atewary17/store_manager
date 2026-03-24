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
    return false if confirmed?

    ActiveRecord::Base.transaction do
      # Compute totals from items
      # Recompute unit_rate = total_amount / quantity for each item
      purchase_invoice_items.each do |item|
        qty   = item.quantity.to_f
        total = item.total_amount.to_f
        item.unit_rate = (qty > 0 && total > 0) ? (total / qty).round(4) : 0
        # Compute per-item taxable and tax amounts from stored GST %
        cgst_pct = item.metadata['cgst_percent'].to_f
        sgst_pct = item.metadata['sgst_percent'].to_f
        igst_pct = item.metadata['igst_percent'].to_f
        total_gst_pct = cgst_pct + sgst_pct + igst_pct
        if total_gst_pct > 0
          taxable = (total / (1 + total_gst_pct / 100.0)).round(2)
          item.metadata = item.metadata.merge(
            'taxable_amount' => taxable,
            'cgst_amount'    => (taxable * cgst_pct / 100.0).round(2),
            'sgst_amount'    => (taxable * sgst_pct / 100.0).round(2),
            'igst_amount'    => (taxable * igst_pct / 100.0).round(2)
          )
        else
          item.metadata = item.metadata.merge('taxable_amount' => total)
        end
        item.save!
      end

      # Aggregate totals
      self.total_taxable_amount = purchase_invoice_items.sum { |i| i.metadata['taxable_amount'].to_f }
      self.total_tax_amount     = purchase_invoice_items.sum { |i|
        (i.metadata['cgst_amount'].to_f + i.metadata['sgst_amount'].to_f + i.metadata['igst_amount'].to_f)
      }
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