# app/models/customer.rb
class Customer < ApplicationRecord

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  has_many   :sales_invoices, dependent: :restrict_with_error
  has_many   :sale_payments,  dependent: :restrict_with_error

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }
  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:name) }

  # ── Validations ───────────────────────────────────────────────
  validates :name, presence: true

  # ── Callbacks ─────────────────────────────────────────────────
  before_save :strip_whitespace

  # ── Helpers ───────────────────────────────────────────────────
  def display_name
    phone.present? ? "#{name} (#{phone})" : name
  end

  def address
    metadata['address'].presence
  end

  def can_delete?
    sales_invoices.none?
  end

  private

  def strip_whitespace
    self.name  = name.strip  if name.present?
    self.phone = phone.strip if phone.present?
    self.gstin = gstin.strip if gstin.present?
  end

end
