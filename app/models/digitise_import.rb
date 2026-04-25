# app/models/digitise_import.rb
class DigitiseImport < ApplicationRecord

  STATUSES = %w[pending processing retrying review confirmed failed stopped].freeze

  belongs_to :organisation
  belongs_to :user
  belongs_to :purchase_invoice, optional: true

  validates :status, inclusion: { in: STATUSES }

  # All queries must be scoped by organisation_id — multi-tenant safety
  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }
  scope :recent,   -> { order(created_at: :desc) }
  scope :pending,  -> { where(status: 'pending') }
  scope :review,   -> { where(status: 'review') }

  # Group imports that belong to the same multi-page invoice upload session
  scope :for_session, ->(sid) { where(session_id: sid) }

  # ── Parsed data accessors ──────────────────────────────────────────────────

  def attempt_log
    self[:attempt_log] || []
  end

  def parsed_header
    parsed_data['header'] || {}
  end

  def parsed_items
    parsed_data['items'] || []
  end

  def parsed_supplier
    parsed_data['supplier'] || {}
  end

  def parsed_meta
    parsed_data['_meta'] || {}
  end

  # ── File type helpers ──────────────────────────────────────────────────────

  def pdf?
    file_content_type == 'application/pdf'
  end

  def image?
    file_content_type&.start_with?('image/')
  end

  def file_size_human
    return '—' unless file_size.present?
    if file_size < 1024
      "#{file_size} B"
    elsif file_size < 1_048_576
      "#{(file_size / 1024.0).round(1)} KB"
    else
      "#{(file_size / 1_048_576.0).round(1)} MB"
    end
  end

  # ── Page awareness ─────────────────────────────────────────────────────────

  # Total pages reported by the AI (from the invoice footer "Page X of N")
  def ai_page_count
    page_count.to_i
  end

  # Pages we actually sent to the AI
  def ai_pages_scanned
    pages_scanned.to_i
  end

  # How many pages are missing
  def missing_page_count
    return 0 if ai_page_count <= 0
    [ai_page_count - ai_pages_scanned, 0].max
  end

  def pages_missing?
    missing_page_count > 0
  end

  # True when only the LAST page(s) are missing.
  # Used for the "last page is usually blank" smart message.
  def only_last_pages_missing?
    return false unless pages_missing?
    # pages_data tells us which page numbers had items
    pages_with_items = parsed_meta.dig('pages_data')&.select { |p| p['item_count'].to_i > 0 }
    return false if pages_with_items.nil?

    # The highest scanned page with items
    max_item_page = pages_with_items.map { |p| p['page_number'].to_i }.max.to_i
    # If the highest page with items covers up to the last scanned page, then
    # the missing pages trail at the end
    max_item_page >= ai_pages_scanned
  end

  # Human-readable page status message for the intelligence box
  def page_status_message
    return nil if ai_page_count <= 0

    if !pages_missing?
      "All #{ai_page_count} page#{'s' if ai_page_count > 1} scanned — #{parsed_items.size} items captured."
    elsif only_last_pages_missing?
      missing = missing_page_count
      "#{ai_pages_scanned} of #{ai_page_count} pages uploaded — #{missing} page#{'s' if missing > 1} missing. " \
      "The last page of most supplier invoices is a terms/acknowledgement page with no items. " \
      "You can safely proceed, or upload the remaining page(s) to be sure."
    else
      missing = missing_page_count
      "#{ai_pages_scanned} of #{ai_page_count} pages uploaded — #{missing} page#{'s' if missing > 1} missing. " \
      "Item data may be incomplete. Please upload all pages before confirming."
    end
  end

  # Severity: :ok, :warn, :error
  def page_status_severity
    return :ok if ai_page_count <= 0 || !pages_missing?
    only_last_pages_missing? ? :warn : :error
  end

  # ── Invoice intelligence summary ───────────────────────────────────────────

  def invoice_summary
    hdr = parsed_header
    {
      invoice_number: hdr['invoice_number'].presence || '—',
      invoice_date:   hdr['invoice_date'].presence   || '—',
      supplier_name:  parsed_supplier['name'].presence || '—',
      item_count:     parsed_items.size,
      total_amount:   hdr['total_amount'].to_f,
      page_count:     ai_page_count,
      pages_scanned:  ai_pages_scanned,
      pages_missing:  missing_page_count,
      page_status:    page_status_message,
      severity:       page_status_severity
    }
  end
end
