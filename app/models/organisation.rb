# app/models/organisation.rb
class Organisation < ApplicationRecord
  has_many :users,          dependent: :destroy
  has_many :scrape_sources, dependent: :destroy
  has_many :organisation_product_categories, dependent: :destroy
  has_many :product_categories, through: :organisation_product_categories

  enum subscription_plan: { basic: 'basic', pro: 'pro', enterprise: 'enterprise' }
  enum status: { active: 0, inactive: 1 }

  # ── Validations ───────────────────────────────────────────────────────────
  validates :name, presence: true
  validates :gst_number, uniqueness: true, allow_blank: true

  # state is critical for intra/inter-state GST determination on every invoice.
  # Without it, ALL purchases and sales default to intra-state (CGST+SGST).
  validates :state, length: { maximum: 100 }, allow_blank: true
  validates :state_code, format: { with: /\A\d{1,2}\z/, message: 'must be 1-2 digits' }, allow_blank: true
  validates :pan, format: { with: /\A[A-Z]{5}[0-9]{4}[A-Z]\z/, message: 'must be 10 characters (e.g. AAACA3622K)' }, allow_blank: true

  # NOTE: gst_number is the legacy GSTIN column (existing).
  # The migration 20260326000002 added a separate :gstin column — we alias it
  # back to gst_number so there is a single source of truth.
  # Use gst_number everywhere in code; gstin column is kept for DB compat only.
  before_save :sync_gstin

  has_many :organisation_products, dependent: :destroy
  has_many :products, through: :organisation_products

  # ── GST helpers ───────────────────────────────────────────────────────────
  def gstin_display
    gst_number.presence || '—'
  end

  def gst_registered?
    gst_number.present?
  end

  # All products enrolled in this org's catalogue (active only)
  def available_products
    Product.for_org(self).includes(:brand, :base_uom, :product_category)
  end

  private

  # Keep the :gstin column (added by migration 20260326000002) in sync with
  # :gst_number so any code that reads either column gets the same value.
  def sync_gstin
    self.gstin = gst_number if has_attribute?(:gstin)
  end
end