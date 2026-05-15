# app/controllers/purchasing/digitise_controller.rb
class Purchasing::DigitiseController < Purchasing::BaseController

  before_action :set_import, only: [:show, :confirm, :retry, :stop, :raw_response]

  ACCEPTED_TYPES = %w[
    application/pdf
    image/jpeg
    image/jpg
    image/png
    image/webp
  ].freeze

  MAX_FILE_SIZE    = 10.megabytes
  MAX_FILES_PER_UPLOAD = 10

  # GET /purchasing/digitise
  def index
    base = DigitiseImport.for_org(@organisation.id)
    @imports = base.includes(:user, :purchase_invoice).recent.limit(50)

    if current_user.super_admin?
      today      = Date.current.beginning_of_day
      active_prov = ENV.fetch('INVOICE_AI_PROVIDER', 'groq').downcase

      by_provider_raw = base.group(
        Arel.sql("COALESCE(ai_provider, '#{active_prov}')")
      ).select(Arel.sql(
        "COALESCE(ai_provider, '#{active_prov}') as ai_provider, " \
        "count(*) as total_count, " \
        "sum(case when status in ('review','confirmed') then 1 else 0 end) as success_count, " \
        "sum(case when status = 'failed' then 1 else 0 end) as failed_count"
      ))

      today_by_provider_raw = base.where('created_at >= ?', today)
                                  .group(Arel.sql("COALESCE(ai_provider, '#{active_prov}')"))
                                  .count

      @stats = {
        total:             base.count,
        success:           base.where(status: %w[review confirmed]).count,
        failed:            base.where(status: 'failed').count,
        pending:           base.where(status: %w[pending processing retrying]).count,
        by_provider:       by_provider_raw.index_by(&:ai_provider),
        today_by_provider: today_by_provider_raw,
        daily_limits:      { 'groq' => 14_400, 'openrouter' => 999, 'gemini' => 1_500 }
      }
    end
  end

  # GET /purchasing/digitise/:id/raw_response  (superadmin only)
  def raw_response
    unless current_user.super_admin?
      redirect_to purchasing_digitise_path(@import), alert: 'Not authorised.'
    end
  end

  # GET /purchasing/digitise/new
  def new
    # just renders the upload form
  end

  # POST /purchasing/digitise
  def create
    files = collect_uploaded_files

    if files.empty?
      redirect_to new_purchasing_digitise_path, alert: 'Please select at least one file to upload.'
      return
    end

    if files.size > MAX_FILES_PER_UPLOAD
      redirect_to new_purchasing_digitise_path,
        alert: "Too many files. Maximum #{MAX_FILES_PER_UPLOAD} files per upload."
      return
    end

    invalid = files.reject { |f| f.content_type.in?(ACCEPTED_TYPES) }
    if invalid.any?
      redirect_to new_purchasing_digitise_path,
        alert: "Unsupported file type: #{invalid.map(&:original_filename).join(', ')}. " \
               "Please upload PDF, JPG, or PNG files."
      return
    end

    oversized = files.select { |f| f.size > MAX_FILE_SIZE }
    if oversized.any?
      redirect_to new_purchasing_digitise_path,
        alert: "File(s) too large: #{oversized.map(&:original_filename).join(', ')}. Maximum 10 MB each."
      return
    end

    # All files in this upload share a session_id so they can be linked
    # to the same invoice if the user uploads multiple pages separately.
    session_id = SecureRandom.uuid

    imports = files.map do |file|
      raw_bytes   = file.read
      base64_data = Base64.strict_encode64(raw_bytes)

      DigitiseImport.create!(
        organisation:      @organisation,
        user:              current_user,
        status:            'pending',
        file_name:         file.original_filename,
        file_size:         file.size,
        file_content_type: file.content_type,
        file_data:         base64_data,
        session_id:        session_id
      )
    end

    imports.each { |imp| DigitiseImportJob.perform_later(imp.id) }

    if imports.size == 1
      redirect_to purchasing_digitise_path(imports.first),
        notice: 'Invoice uploaded — AI is reading it now. This usually takes 10–20 seconds.'
    else
      redirect_to purchasing_digitise_path(imports.first),
        notice: "#{imports.size} pages uploaded — AI is processing them. " \
                "Results will be merged into one invoice."
    end
  end

  # GET /purchasing/digitise/:id
  TERMINAL_STATUSES = %w[review failed confirmed stopped].freeze

  def show
    # Load all imports in the same session — scoped to organisation (multi-tenant).
    # For single-file uploads (no session_id), this is just [@import].
    @session_imports = if @import.session_id.present?
      DigitiseImport.for_org(@organisation.id)
                    .for_session(@import.session_id)
                    .order(:created_at)
                    .to_a
    else
      [@import]
    end

    @session_pending = @session_imports.select { |i| %w[pending processing retrying].include?(i.status) }

    if @import.status == 'review'
      # Items merged from every sibling that has finished — not just the primary import
      review_imports = @session_imports.select { |i| i.status == 'review' }
      @merged_items  = review_imports.flat_map(&:parsed_items)
      # Page groups used to render "Page N" separators in the view
      @item_pages    = review_imports.each_with_index.map { |imp, i| { page: i + 1, items: imp.parsed_items } }

      # Session-level page stats — each uploaded image = 1 DigitiseImport with pages_scanned=1,
      # so we must aggregate across the session rather than reading from @import alone.
      @session_pages_scanned = review_imports.size
      @session_page_count    = [review_imports.map(&:ai_page_count).max.to_i,
                                @session_pages_scanned].max
      # Grand total: use the session import that reported the highest total_amount
      # (the summary/totals page has the real figure; individual pages may show 0).
      @session_grand_total   = review_imports
                                 .map { |i| i.parsed_header['total_amount'].to_f }
                                 .max.to_f

      # Build lightbox image list for all session imports
      @lightbox_images = @session_imports.filter_map do |imp|
        if imp.preview_image.present?
          { src: "data:image/jpeg;base64,#{imp.preview_image}",
            label: imp.file_name }
        elsif imp.image? && imp.file_data.present?
          safe_mime = imp.file_content_type.in?(%w[image/jpeg image/jpg image/png image/webp]) ?
                        imp.file_content_type : 'image/jpeg'
          { src: "data:#{safe_mime};base64,#{imp.file_data}",
            label: imp.file_name }
        end
      end

      codes = @merged_items.map { |i| sanitise_material_code(i['material_code'].to_s) }.compact
      @product_by_code = Product.includes(:base_uom)
                                .where(material_code: codes)
                                .index_by(&:material_code)

      # Append mode: check if a draft invoice already exists for this invoice number.
      # Always scoped to organisation — multi-tenant safety.
      invoice_number = @import.parsed_header['invoice_number'].presence
      if invoice_number.present?
        @existing_invoice = PurchaseInvoice
          .for_org(@organisation.id)
          .where(invoice_number: invoice_number, status: 'draft')
          .first

        if @existing_invoice
          @confirmed_items = @existing_invoice.purchase_invoice_items
                                              .includes(:product)
                                              .order(:created_at)
          @duplicates = @existing_invoice.duplicate_items(@merged_items)
        end
      end
    end

    respond_to do |format|
      format.html
      format.json do
        # Terminal only when ALL session siblings are done (no pending/processing left)
        session_all_terminal = @session_imports.none? { |i| %w[pending processing retrying].include?(i.status) }
        render json: {
          status:          @import.status,
          terminal:        TERMINAL_STATUSES.include?(@import.status) && session_all_terminal,
          attempt:         @import.attempt_count,
          error:           @import.error_message,
          attempt_log:     @import.attempt_log,
          session_pending: @session_pending.size
        }
      end
    end
  end

  # POST /purchasing/digitise/:id/confirm
  def confirm
    unless @import.status == 'review'
      redirect_to purchasing_digitise_path(@import), alert: 'Import is not ready for confirmation.'
      return
    end

    # For multi-image sessions, merge items from all sibling imports into the primary
    # BEFORE applying user edits, so the form's indexed items map correctly.
    if @import.session_id.present?
      sibling_imports = DigitiseImport.for_org(@organisation.id)
                                      .for_session(@import.session_id)
                                      .where(status: 'review')
                                      .order(:created_at)
                                      .to_a
      if sibling_imports.size > 1
        @import.parsed_data = @import.parsed_data.merge(
          'items' => sibling_imports.flat_map(&:parsed_items)
        )
      end
    end

    if params[:parsed_data].present?
      @import.parsed_data = deep_merge_params(@import.parsed_data, params[:parsed_data])
    end

    hdr            = @import.parsed_header
    invoice_number = hdr['invoice_number'].presence

    # Detect append mode — existing DRAFT invoice with same invoice_number, same org
    existing_invoice = nil
    if invoice_number.present?
      existing_invoice = PurchaseInvoice
        .for_org(@organisation.id)
        .where(invoice_number: invoice_number, status: 'draft')
        .first
    end

    saved_invoice = nil

    ActiveRecord::Base.transaction do
      if existing_invoice
        append_items_to_invoice(existing_invoice, @import)
        saved_invoice = existing_invoice
      else
        invoice = build_invoice_from_import(@import)
        unless invoice.save
          raise ActiveRecord::RecordInvalid.new(invoice)
        end
        saved_invoice = invoice
      end

      @import.update!(
        status:              'confirmed',
        purchase_invoice_id: saved_invoice.id,
        file_data:           nil   # clear blob — no longer needed
      )
    end

    # Mark all other session imports as confirmed and link to the same invoice.
    # Scoped to organisation — multi-tenant safety.
    if @import.session_id.present?
      DigitiseImport.for_org(@organisation.id)
                    .for_session(@import.session_id)
                    .where.not(id: @import.id)
                    .update_all(
                      status:              'confirmed',
                      purchase_invoice_id: saved_invoice.id,
                      file_data:           nil,
                      updated_at:          Time.current
                    )
    end

    begin
      ActivityLogger.log(
        organisation:     @organisation,
        user:             current_user,
        activity_type:    'invoice_scan',
        activity_subtype: 'confirmed',
        description:      "Invoice scanned and saved — #{saved_invoice.invoice_number.presence || saved_invoice.display_number}",
        reference:        saved_invoice,
        metadata:         {
          invoice_number: saved_invoice.invoice_number,
          supplier:       saved_invoice.supplier&.name,
          import_id:      @import.id
        }.compact
      )
    rescue => e
      Rails.logger.warn("[ActivityLog] invoice_scan #{@import.id}: #{e.message}")
    end

    sup_msg = @supplier_matched ? 'Supplier matched.' : 'New supplier created.'
    redirect_to purchasing_purchase_invoice_path(saved_invoice),
      notice: "Invoice digitised and saved as draft. #{sup_msg} " \
              "Review items, then confirm to update stock."

  rescue ActiveRecord::RecordInvalid => e
    redirect_to purchasing_digitise_path(@import),
      alert: "Could not save: #{e.message}"
  rescue => e
    redirect_to purchasing_digitise_path(@import),
      alert: "Error saving invoice: #{e.message}"
  end

  # POST /purchasing/digitise/:id/stop
  def stop
    if %w[pending processing retrying failed].include?(@import.status)
      @import.update!(status: 'stopped')
    end
    redirect_to purchasing_digitise_path(@import), notice: 'Processing stopped.'
  end

  # POST /purchasing/digitise/:id/retry
  def retry
    unless %w[failed stopped].include?(@import.status)
      redirect_to purchasing_digitise_path(@import), alert: 'Only failed imports can be retried.'
      return
    end

    @import.update!(status: 'pending', error_message: nil)
    DigitiseImportJob.perform_later(@import.id)

    redirect_to purchasing_digitise_path(@import),
      notice: 'Retrying — AI is reading the invoice again.'
  end

  private

  def set_import
    # Always scope to organisation — multi-tenant safety
    @import = DigitiseImport.for_org(@organisation.id).find(params[:id])
  end

  # Support both single file (name="file") and multi-file (name="files[]")
  def collect_uploaded_files
    if params[:files].present?
      Array(params[:files]).compact
    elsif params[:file].present?
      [params[:file]]
    else
      []
    end
  end

  # ── Append mode: add new items to an existing draft invoice ───────────────
  #
  # Duplicate items (same material_code + qty + total) are skipped with a warning.
  # Confirmed invoices cannot be appended to — only drafts.
  #
  def append_items_to_invoice(invoice, import)
    items = import.parsed_items

    duplicates = invoice.duplicate_items(items)
    if duplicates.any?
      dup_desc = duplicates.map { |d| d['description'].presence || d['material_code'] }.join(', ')
      raise "Duplicate items detected and skipped: #{dup_desc}. " \
            "These items already exist in invoice #{invoice.display_number}."
    end

    items.each do |item|
      qty   = item['quantity'].to_f
      total = item['total_amount'].to_f
      next if qty == 0 && total == 0

      raw_code            = item['material_code'].to_s.strip
      clean_material_code = sanitise_material_code(raw_code)
      rescued_hsn = if clean_material_code.nil? && raw_code.present?
                      raw_code.gsub(/\AHSN[-\s]*/i, '').gsub(/\D/, '').presence
                    end
      effective_hsn  = item['hsn_code'].presence || rescued_hsn
      effective_unit = item['unit'].presence
      line_disc_pct  = item['discount_percent'].to_f
      line_disc_amt  = item['discount_amount'].to_f

      invoice.purchase_invoice_items.create!(
        product:      nil,
        unmatched:    true,
        quantity:     qty,
        unit_rate:    item['unit_rate'].to_f,
        total_amount: total,
        metadata: {
          'material_code'    => clean_material_code,
          'description'      => item['description'],
          'raw_description'  => item['description'],
          'hsn_code'         => effective_hsn,
          'pack_size'        => item['pack_size'],
          'num_packs'        => item['num_packs'],
          'volume'           => item['volume'].to_f > 0 ? item['volume'].to_f : nil,
          'unit'             => effective_unit,
          'rate_per_pack'    => item['rate_per_pack'].to_f,
          'discount_percent' => line_disc_pct,
          'discount_amount'  => line_disc_amt,
          'taxable_amount'   => item['taxable_amount'].to_f,
          'cgst_percent'     => item['cgst_percent'].to_f,
          'cgst_amount'      => item['cgst_amount'].to_f,
          'sgst_percent'     => item['sgst_percent'].to_f,
          'sgst_amount'      => item['sgst_amount'].to_f,
          'igst_percent'     => item['igst_percent'].to_f,
          'igst_amount'      => item['igst_amount'].to_f,
          'appended_from_import' => import.id
        }.compact_blank
      )
    end

    @supplier_matched = true
  end

  # ── Build a new PurchaseInvoice from parsed import data ───────────────────
  def build_invoice_from_import(import)
    hdr      = import.parsed_header
    sup_data = import.parsed_supplier
    items    = import.parsed_items

    supplier = find_or_create_supplier(sup_data)

    invoice = PurchaseInvoice.new(
      organisation:     @organisation,
      user:             current_user,
      supplier:         supplier,
      status:           'draft',
      invoice_number:   hdr['invoice_number'].presence,
      invoice_date:     parse_date(hdr['invoice_date']),
      delivery_date:    parse_date(hdr['delivery_date']) || Date.today,
      payment_due_date: parse_date(params[:payment_due_date]),
      metadata: {
        'delivery_number'       => hdr['delivery_number'],
        'po_reference'          => hdr['po_reference'],
        'place_of_supply'       => hdr['place_of_supply'],
        'irn'                   => hdr['irn'],
        'eway_bill'             => hdr['eway_bill'],
        'lr_number'             => hdr['lr_number'],
        'transporter'           => hdr['transporter'],
        'vehicle_number'        => hdr['vehicle_number'],
        'amount_in_words'       => hdr['amount_in_words'],
        'cash_discount_amount'  => hdr['cash_discount_amount'].to_f,
        'cash_discount_percent' => hdr['cash_discount_percent'].to_f,
        'digitised'             => true,
        'digitise_import_id'    => import.id
      }.compact_blank
    )

    items.each do |item|
      qty   = item['quantity'].to_f
      total = item['total_amount'].to_f
      next if qty == 0 && total == 0

      raw_code            = item['material_code'].to_s.strip
      clean_material_code = sanitise_material_code(raw_code)
      rescued_hsn = if clean_material_code.nil? && raw_code.present?
                      raw_code.gsub(/\AHSN[-\s]*/i, '').gsub(/\D/, '').presence
                    end
      effective_hsn  = item['hsn_code'].presence || rescued_hsn
      product        = nil
      effective_unit = product&.base_uom&.name.presence || item['unit'].presence
      line_disc_pct  = item['discount_percent'].to_f
      line_disc_amt  = item['discount_amount'].to_f

      invoice.purchase_invoice_items.build(
        product:      product,
        unmatched:    product.nil?,
        quantity:     qty,
        unit_rate:    item['unit_rate'].to_f,
        total_amount: total,
        metadata: {
          'material_code'    => clean_material_code,
          'description'      => item['description'],
          'raw_description'  => item['description'],
          'hsn_code'         => effective_hsn,
          'pack_size'        => item['pack_size'],
          'num_packs'        => item['num_packs'],
          'volume'           => item['volume'].to_f > 0 ? item['volume'].to_f : nil,
          'unit'             => effective_unit,
          'rate_per_pack'    => item['rate_per_pack'].to_f,
          'discount_percent' => line_disc_pct,
          'discount_amount'  => line_disc_amt,
          'taxable_amount'   => item['taxable_amount'].to_f,
          'cgst_percent'     => item['cgst_percent'].to_f,
          'cgst_amount'      => item['cgst_amount'].to_f,
          'sgst_percent'     => item['sgst_percent'].to_f,
          'sgst_amount'      => item['sgst_amount'].to_f,
          'igst_percent'     => item['igst_percent'].to_f,
          'igst_amount'      => item['igst_amount'].to_f
        }.compact_blank
      )
    end

    invoice
  end

  def find_or_create_supplier(sup_data)
    return nil if sup_data.blank? || sup_data['name'].blank?

    supplier         = nil
    supplier_matched = false

    # 1. GSTIN match — scoped to organisation
    if sup_data['gstin'].present?
      supplier = Supplier.where(organisation: @organisation)
                         .find_by(gstin: sup_data['gstin'].upcase.strip)
      supplier_matched = supplier.present?
    end

    # 2. Normalised name match — scoped to organisation
    unless supplier
      normalised_input = sup_data['name'].downcase.gsub(/[^a-z0-9]/, '')
      candidate = Supplier.where(organisation: @organisation).find do |s|
        s.name.downcase.gsub(/[^a-z0-9]/, '') == normalised_input
      end
      if candidate
        supplier         = candidate
        supplier_matched = true
      end
    end

    # 3. Create new supplier — scoped to organisation
    unless supplier
      supplier = Supplier.create!(
        organisation: @organisation,
        name:         sup_data['name'].strip,
        gstin:        sup_data['gstin'].presence&.upcase&.strip,
        pan:          sup_data['pan'].presence&.upcase&.strip,
        state:        sup_data['state'].presence,
        state_code:   sup_data['state_code'].presence,
        active:       true,
        metadata:     { 'address' => sup_data['address'], 'digitise_created' => true }.compact_blank
      )
      supplier_matched = false
    end

    @supplier_matched = supplier_matched
    supplier
  end

  HSN_PATTERN = /\AHSN[-\s]/i

  helper_method :sanitise_material_code
  def sanitise_material_code(raw)
    return nil if raw.blank?
    code = raw.to_s.strip
    return nil if code.match?(HSN_PATTERN)
    return nil if code.match?(/\A\d{4,8}\z/)
    code
  end

  def parse_date(val)
    return nil if val.blank? || val.to_s == 'null'
    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end

  def deep_merge_params(base, incoming)
    flat = incoming.respond_to?(:to_unsafe_h) ? incoming.to_unsafe_h.deep_stringify_keys
                                               : incoming.to_h.deep_stringify_keys

    base.merge(flat) do |key, old_val, new_val|
      if key == 'items' && new_val.is_a?(Hash) && new_val.keys.all? { |k| k.to_s =~ /\A\d+\z/ }
        new_val.sort_by { |k, _| k.to_i }.each_with_index.map do |(_, item_params), i|
          orig = old_val.is_a?(Array) ? (old_val[i] || {}) : {}
          orig.merge(item_params.respond_to?(:to_unsafe_h) ? item_params.to_unsafe_h.deep_stringify_keys
                                                            : item_params.to_h.deep_stringify_keys)
        end
      elsif old_val.is_a?(Hash) && (new_val.is_a?(Hash) || new_val.respond_to?(:to_unsafe_h))
        deep_merge_params(old_val, new_val)
      else
        new_val.presence || old_val
      end
    end
  end
end
