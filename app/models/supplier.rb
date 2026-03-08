# app/models/supplier.rb
class Supplier < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  has_many   :purchase_invoices, dependent: :restrict_with_error

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }
  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:name) }

  # ── Validations ───────────────────────────────────────────────
  validates :name, presence: true, uniqueness: { scope: :organisation_id, case_sensitive: false }

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace

  # ── Cache helpers ─────────────────────────────────────────────
  def self.cached_count
    Rails.cache.fetch('supplier/count', expires_in: 10.minutes) { count }
  end

  def display_name
    gstin.present? ? "#{name} (#{gstin})" : name
  end

  def address
    metadata['address'].presence
  end

  def can_delete?
    purchase_invoices.none?
  end

  private

  def strip_whitespace
    self.name  = name.strip  if name.present?
    self.gstin = gstin.strip if gstin.present?
    self.pan   = pan.strip   if pan.present?
  end

end