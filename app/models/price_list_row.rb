# app/models/price_list_row.rb
class PriceListRow < ApplicationRecord

  MATCH_STATUSES = %w[pending matched unmatched ambiguous].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :brand,           optional: true
  belongs_to :matched_product, class_name: 'Product', optional: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :pending,          -> { where(match_status: 'pending') }
  scope :matched,          -> { where(match_status: 'matched') }
  scope :unmatched,        -> { where(match_status: 'unmatched') }
  scope :ambiguous,        -> { where(match_status: 'ambiguous') }
  scope :for_date,         ->(date) { where(effective_date: date) }
  scope :ordered,          -> { order(effective_date: :desc, product_base_name: :asc) }
  scope :search, ->(q) {
    return all if q.blank?
    term = "%#{q.downcase}%"
    where(
      'LOWER(product_base_name) LIKE ? OR LOWER(shade_name) LIKE ? OR ' \
      'LOWER(shade_code) LIKE ? OR LOWER(prod_code) LIKE ?',
      term, term, term, term
    )
  }

  # ── Validations ───────────────────────────────────────────────
  validates :product_base_name, presence: true
  validates :dealer_price,      presence: true,
                                numericality: { greater_than_or_equal_to: 0 }
  validates :effective_date,    presence: true
  validates :match_status,      inclusion: { in: MATCH_STATUSES }

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace

  # ── Helpers ───────────────────────────────────────────────────
  def matched?  = match_status == 'matched'
  def pending?  = match_status == 'pending'
  def unmatched? = match_status == 'unmatched'
  def ambiguous? = match_status == 'ambiguous'

  private

  def strip_whitespace
    %i[product_base_name prod_code shade_name shade_code pack_code].each do |f|
      self[f] = self[f].strip if self[f].present?
    end
  end

end
