# app/models/referrer.rb
class Referrer < ApplicationRecord

  TRADES = %w[painter contractor electrician plumber carpenter mason civil other].freeze

  # ── Associations ──────────────────────────────────────────────
  belongs_to :organisation
  has_many   :sales_invoices, dependent: :nullify

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }
  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:name) }
  scope :by_trade, ->(t) { where(trade: t) }

  # ── Validations ───────────────────────────────────────────────
  validates :name,  presence: true
  validates :trade, inclusion: { in: TRADES }
  validates :phone, uniqueness: { scope: :organisation_id,
                                  message: 'already registered as a referrer' },
                    allow_blank: true

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace

  # ── Helpers ───────────────────────────────────────────────────
  def display_name
    phone.present? ? "#{name} (#{phone})" : name
  end

  def display_trade
    trade.humanize
  end

  def total_invoices
    sales_invoices.confirmed.count
  end

  def total_referred_amount
    sales_invoices.confirmed.sum(:total_amount).to_f.round(2)
  end

  def total_outstanding
    sales_invoices.confirmed.sum(:total_amount).to_f -
      sales_invoices.confirmed.joins(:sale_payments)
                              .sum('sale_payments.amount').to_f
  end

  def last_referral_date
    sales_invoices.confirmed.maximum(:invoice_date)
  end

  def can_delete?
    sales_invoices.none?
  end

  private

  def strip_whitespace
    self.name  = name.strip  if name.present?
    self.phone = phone.strip if phone.present?
    self.area  = area.strip  if area.present?
  end

end
