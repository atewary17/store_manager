# app/models/organisation.rb
class Organisation < ApplicationRecord
  has_many :users,          dependent: :destroy
  has_many :scrape_sources, dependent: :destroy
  has_many :organisation_product_categories, dependent: :destroy
  has_many :product_categories, through: :organisation_product_categories
  has_many :activity_logs,  dependent: :destroy

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

  # ── Settings helpers ─────────────────────────────────────────────────────
  def stock_updates_locked?
    settings['stock_updates_locked'] == true
  end

  def update_setting!(key, value)
    update!(settings: settings.merge(key.to_s => value))
  end

  # ── Invoice numbering ────────────────────────────────────────────────────
  # Thread-safe, per-org sequential number generator.
  # Uses SELECT FOR UPDATE on this org's row so two simultaneous confirms on
  # the SAME org cannot draw the same counter. Different orgs lock different
  # rows, so they are completely independent.
  INVOICE_FORMATS = %w[prefix_date_serial prefix_serial serial_only].freeze

  def next_invoice_number!
    with_lock do
      start_from = [settings['invoice_number_start'].to_i, 1].max
      counter    = settings['invoice_number_counter'].present? ?
                     settings['invoice_number_counter'].to_i + 1 :
                     start_from
      # update_columns bypasses callbacks (avoids re-running sync_gstin, etc.)
      update_columns(settings: settings.merge('invoice_number_counter' => counter))
      build_invoice_number(counter)
    end
  end

  def invoice_number_preview
    counter = (settings['invoice_number_counter'] || settings['invoice_number_start'].to_i - 1 || 0).to_i + 1
    build_invoice_number(counter)
  end

  # ── Tinting counter ─────────────────────────────────────────────────────
  # Returns a hash of { "base_product_id_string" => total_litres } covering
  # all paint sales since the most recent tinting_update log.
  # Rescues so a missing activity_logs table never breaks a page load.
  def tinting_litres_since_reset
    last_reset = activity_logs
                   .where(activity_type: 'tinting_update')
                   .maximum(:created_at)

    scope = activity_logs.where(activity_type: 'sales').where.not(quantity_litres: nil)
    scope = scope.where('created_at > ?', last_reset) if last_reset
    scope.group("metadata->>'base_product_id'").sum(:quantity_litres)
  rescue StandardError
    {}
  end

  # All products enrolled in this org's catalogue (active only)
  def available_products
    Product.for_org(self).includes(:brand, :base_uom, :product_category)
  end

  private

  def build_invoice_number(counter)
    serial  = counter.to_s.rjust(5, '0')
    prefix  = settings['invoice_number_prefix'].to_s.strip.upcase
    fmt     = settings['invoice_number_format'].presence || 'serial_only'

    case fmt
    when 'prefix_date_serial'
      date = Date.today.strftime('%d%m%y')
      prefix.present? ? "#{prefix}-#{date}-#{serial}" : "#{date}-#{serial}"
    when 'prefix_serial'
      prefix.present? ? "#{prefix}-#{serial}" : serial
    else
      serial
    end
  end

  # Keep the :gstin column (added by migration 20260326000002) in sync with
  # :gst_number so any code that reads either column gets the same value.
  def sync_gstin
    self.gstin = gst_number if has_attribute?(:gstin)
  end
end