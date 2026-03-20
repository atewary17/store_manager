# app/models/purchase_payment.rb
class PurchasePayment < ApplicationRecord

  PAYMENT_MODES = %w[cash cheque bank_transfer upi neft rtgs].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :purchase_invoice
  belongs_to :supplier, optional: true
  belongs_to :user

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,      ->(org_id) { where(organisation_id: org_id) }
  scope :for_supplier, ->(sid)    { where(supplier_id: sid) }
  scope :recent,                  -> { order(payment_date: :desc, created_at: :desc) }
  scope :chronological,           -> { order(payment_date: :asc,  created_at: :asc) }

  # ── Validations ───────────────────────────────────────────────
  validates :payment_date, presence: true
  validates :amount,       presence: true,
                           numericality: { greater_than: 0 }
  validates :payment_mode, inclusion: { in: PAYMENT_MODES }
  validate  :amount_within_outstanding

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :copy_supplier_from_invoice
  before_create     :assign_payment_number

  # ── Helpers ───────────────────────────────────────────────────
  def payment_label
    payment_number.presence || "PP-#{id}"
  end

  private

  def copy_supplier_from_invoice
    self.supplier_id ||= purchase_invoice&.supplier_id
  end

  def assign_payment_number
    return if payment_number.present?
    date_part = (payment_date || Date.today).strftime('%Y%m%d')
    last_seq  = PurchasePayment
                  .where(organisation_id: organisation_id)
                  .where('payment_number LIKE ?', "PP-#{date_part}-%")
                  .order(:payment_number).last
                  &.payment_number&.split('-')&.last&.to_i || 0
    self.payment_number = "PP-#{date_part}-#{(last_seq + 1).to_s.rjust(4, '0')}"
  end

  def amount_within_outstanding
    return unless purchase_invoice && amount
    outstanding = purchase_invoice.outstanding_amount
    already_paid = persisted? ? amount_was.to_f : 0
    budget = outstanding + already_paid
    if amount.to_f > budget.round(2)
      errors.add(:amount, "cannot exceed outstanding balance of ₹#{budget.round(2)}")
    end
  end

end
