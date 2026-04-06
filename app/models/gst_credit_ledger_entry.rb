# app/models/gst_credit_ledger_entry.rb
#
# Represents one month's Electronic Credit Ledger entry for an organisation.
# Mirrors the GST portal's ITC balance that carries forward indefinitely.

class GstCreditLedgerEntry < ApplicationRecord

  belongs_to :organisation
  belongs_to :closed_by, class_name: 'User', optional: true

  validates :period_year,  presence: true, numericality: { only_integer: true }
  validates :period_month, presence: true, inclusion: { in: 1..12 }
  validates :organisation_id, uniqueness: { scope: [:period_year, :period_month],
    message: 'already has a ledger entry for this period' }

  scope :for_org,  ->(org_id)     { where(organisation_id: org_id) }
  scope :closed,   ->             { where(period_closed: true) }
  scope :for_year, ->(y)          { where(period_year: y) }

  # ── Finders ────────────────────────────────────────────────────────────

  def self.find_or_build(organisation_id:, year:, month:)
    find_or_initialize_by(
      organisation_id: organisation_id,
      period_year:  year,
      period_month: month
    )
  end

  # Fetch the previous month's closing balance as this month's opening.
  # Returns { igst: 0, cgst: 0, sgst: 0 } if no prior entry exists.
  def self.opening_balance_for(organisation_id:, year:, month:)
    prev_date  = Date.new(year, month, 1).prev_month
    prior = find_by(
      organisation_id: organisation_id,
      period_year:  prev_date.year,
      period_month: prev_date.month
    )
    return { igst: 0.0, cgst: 0.0, sgst: 0.0 } unless prior

    {
      igst: prior.closing_igst.to_f,
      cgst: prior.closing_cgst.to_f,
      sgst: prior.closing_sgst.to_f
    }
  end

  # ── Period helpers ────────────────────────────────────────────────────

  def period_label
    Date.new(period_year, period_month, 1).strftime('%B %Y')
  end

  def total_opening
    (opening_igst + opening_cgst + opening_sgst).round(2)
  end

  def total_period_itc
    (period_igst_itc + period_cgst_itc + period_sgst_itc).round(2)
  end

  def total_closing
    (closing_igst + closing_cgst + closing_sgst).round(2)
  end

  def total_cash
    (cash_igst + cash_cgst + cash_sgst).round(2)
  end

  def open?
    !period_closed?
  end

end
