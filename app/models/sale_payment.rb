# app/models/sale_payment.rb
class SalePayment < ApplicationRecord

  PAYMENT_MODES = %w[cash upi cheque bank_transfer].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :sales_invoice
  belongs_to :customer, optional: true
  belongs_to :user

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,      ->(org_id) { where(organisation_id: org_id) }
  scope :for_customer, ->(cid)    { where(customer_id: cid) }
  scope :recent,                  -> { order(payment_date: :desc, created_at: :desc) }
  scope :chronological,           -> { order(payment_date: :asc,  created_at: :asc)  }

  # ── Validations ───────────────────────────────────────────────
  validates :payment_date, presence: true
  validates :amount,       presence: true,
                           numericality: { greater_than: 0 }
  validates :payment_mode, inclusion: { in: PAYMENT_MODES }
  validate  :amount_within_outstanding

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :copy_customer_from_invoice
  before_create     :assign_receipt_number

  # ── Helpers ───────────────────────────────────────────────────
  def receipt_label
    receipt_number.presence || "RCP-#{id}"
  end

  private

  def copy_customer_from_invoice
    self.customer_id ||= sales_invoice&.customer_id
  end

  def assign_receipt_number
    return if receipt_number.present?
    # Format: RCP-YYYYMMDD-XXXXX  (org-scoped sequential)
    date_part = (payment_date || Date.today).strftime('%Y%m%d')
    last = SalePayment
             .where(organisation_id: organisation_id)
             .where("receipt_number LIKE ?", "RCP-#{date_part}-%")
             .order(:receipt_number)
             .last
             &.receipt_number
    seq = last ? last.split('-').last.to_i + 1 : 1
    self.receipt_number = "RCP-#{date_part}-#{seq.to_s.rjust(4, '0')}"
  end

  def amount_within_outstanding
    return unless sales_invoice && amount
    # Allow up to outstanding balance (existing payments already committed)
    outstanding = sales_invoice.outstanding_amount
    # On update, add back this record's own existing amount
    already_paid = persisted? ? amount_was.to_f : 0
    budget = outstanding + already_paid
    if amount.to_f > budget.round(2)
      errors.add(:amount, "cannot exceed outstanding balance of ₹#{budget.round(2)}")
    end
  end

end
