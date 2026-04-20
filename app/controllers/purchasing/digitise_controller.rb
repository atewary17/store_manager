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

  # GET /purchasing/digitise
  def index
    base = DigitiseImport.for_org(@organisation.id)
    @imports = base.includes(:user, :purchase_invoice).recent.limit(50)

    if current_user.super_admin?
      today = Date.current.beginning_of_day

      # Use COALESCE so records without ai_provider (still processing/failed before
      # provider was recorded) still contribute to the active provider's counts.
      active_prov = ENV.fetch('INVOICE_AI_PROVIDER', 'gemini').downcase

      by_provider_raw = base.group(
        Arel.sql("COALESCE(ai_provider, '#{active_prov}')")
      ).select(Arel.sql(
        "COALESCE(ai_provider, '#{active_prov}') as ai_provider, "         "count(*) as total_count, "         "sum(case when status in ('review','confirmed') then 1 else 0 end) as success_count, "         "sum(case when status = 'failed' then 1 else 0 end) as failed_count"
      ))

      # Today's usage: all records created today regardless of whether ai_provider is set
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
        daily_limits:      { 'gemini' => 1500, 'groq' => 14_400 }
      }
    end
  end

  # GET /purchasing/digitise/:id/raw_response  (superadmin only)
  def raw_response
    unless current_user.super_admin?
      redirect_to purchasing_digitise_path(@import), alert: 'Not authorised.'
      return
    end
  end

  # GET /purchasing/digitise/new
  def new
    # just renders the upload form
  end

  # POST /purchasing/digitise
  def create
    file = params[:file]

    unless file.present?
      redirect_to new_purchasing_digitise_path, alert: 'Please select a file to upload.'
      return
    end

    unless file.content_type.in?(ACCEPTED_TYPES)
      redirect_to new_purchasing_digitise_path,
        alert: 'Unsupported file type. Please upload a PDF, JPG, or PNG.'
      return
    end

    if file.size > 10.megabytes
      redirect_to new_purchasing_digitise_path,
        alert: 'File too large. Maximum size is 10 MB.'
      return
    end

    raw_bytes   = file.read
    base64_data = Base64.strict_encode64(raw_bytes)

    import = DigitiseImport.create!(
      organisation:      @organisation,
      user:              current_user,
      status:            'pending',
      file_name:         file.original_filename,
      file_size:         file.size,
      file_content_type: file.content_type,
      file_data:         base64_data
    )

    DigitiseImportJob.perform_later(import.id)

    redirect_to purchasing_digitise_path(import),
      notice: "Invoice uploaded — AI is reading it now. This usually takes 10–20 seconds."
  end

  # GET /purchasing/digitise/:id
  # Also used as a polling endpoint — returns JSON if requested
  TERMINAL_STATUSES = %w[review failed confirmed stopped].freeze

  def show
    # Pre-build a material_code → product map for the review view (avoids N+1)
    if @import.status == 'review'
      items = @import.parsed_items
      codes = items.map { |i| sanitise_material_code(i['material_code'].to_s) }.compact
      # Fetch from master products table (global) — enrolment happens at confirm time
      @product_by_code = Product.includes(:base_uom)
                                .where(material_code: codes)
                                .index_by(&:material_code)
    end

    respond_to do |format|
      format.html
      format.json do
        render json: {
          status:       @import.status,
          terminal:     TERMINAL_STATUSES.include?(@import.status),
          attempt:      @import.attempt_count,
          error:        @import.error_message,
          attempt_log:  @import.attempt_log
        }
      end
    end
  end

  # POST /purchasing/digitise/:id/confirm
  # Converts parsed_data into a real PurchaseInvoice + items
  def confirm
    unless @import.status == 'review'
      redirect_to purchasing_digitise_path(@import), alert: 'Import is not ready for confirmation.'
      return
    end

    # Merge user edits from the form into parsed_data before saving
    if params[:parsed_data].present?
      @import.parsed_data = deep_merge_params(@import.parsed_data, params[:parsed_data])
    end

    ActiveRecord::Base.transaction do
      invoice = build_invoice_from_import(@import)

      unless invoice.save
        raise ActiveRecord::Rollback
        redirect_to purchasing_digitise_path(@import),
          alert: "Could not save: #{invoice.errors.full_messages.join(', ')}"
        return
      end

      @import.update!(
        status:             'confirmed',
        purchase_invoice_id: invoice.id,
        file_data:           nil   # clear the base64 blob — no longer needed
      )

      sup_msg = @supplier_matched ? "Supplier matched." : "New supplier created."
      redirect_to purchasing_purchase_invoice_path(invoice),
        notice: "Invoice digitised and saved as draft. #{sup_msg} Review items, then confirm to update stock."
    end

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
    @import = DigitiseImport.for_org(@organisation.id).find(params[:id])
  end

  # ── Build a PurchaseInvoice from the parsed + user-edited data ──
  def build_invoice_from_import(import)
    hdr      = import.parsed_header
    sup_data = import.parsed_supplier
    items    = import.parsed_items

    # Find or create supplier
    supplier = find_or_create_supplier(sup_data)

    invoice = PurchaseInvoice.new(
      organisation:    @organisation,
      user:            current_user,
      supplier:        supplier,
      status:          'draft',
      invoice_number:  hdr['invoice_number'].presence,
      invoice_date:    parse_date(hdr['invoice_date']),
      delivery_date:   parse_date(hdr['delivery_date']) || Date.today,
      payment_due_date: parse_date(params[:payment_due_date]),
      metadata: {
        'delivery_number'      => hdr['delivery_number'],
        'po_reference'         => hdr['po_reference'],
        'place_of_supply'      => hdr['place_of_supply'],
        'irn'                  => hdr['irn'],
        'eway_bill'            => hdr['eway_bill'],
        'lr_number'            => hdr['lr_number'],
        'transporter'          => hdr['transporter'],
        'vehicle_number'       => hdr['vehicle_number'],
        'amount_in_words'      => hdr['amount_in_words'],
        'cash_discount_amount' => hdr['cash_discount_amount'].to_f,
        'cash_discount_percent'=> hdr['cash_discount_percent'].to_f,
        'digitised'            => true,
        'digitise_import_id'   => import.id
      }.compact_blank
    )

    items.each do |item|
      qty   = item['quantity'].to_f
      total = item['total_amount'].to_f
      next if qty == 0 && total == 0

      # Sanitise material_code before matching — AI sometimes mixes it with HSN.
      # If the raw value looks like an HSN entry, rescue it into hsn_code.
      raw_code = item['material_code'].to_s.strip
      clean_material_code = sanitise_material_code(raw_code)
      # If raw_code was rejected as a material code, try to salvage HSN from it
      rescued_hsn = if clean_material_code.nil? && raw_code.present?
                      raw_code.gsub(/\AHSN[-\s]*/i, '').gsub(/\D/, '').presence
                    end
      effective_hsn = item['hsn_code'].presence || rescued_hsn
      # TODO Step 4 — replaced by InvoiceProductResolver
      product = nil

      # Use UOM from product table when matched; fall back to AI-extracted unit
      effective_unit = product&.base_uom&.name.presence || item['unit'].presence

      # Per-line cash discount (Asian Paints, Friends Enterprise carry it per line)
      line_disc_pct = item['discount_percent'].to_f
      line_disc_amt = item['discount_amount'].to_f

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

    supplier      = nil
    supplier_matched = false

    # 1. Match by GSTIN — most reliable
    if sup_data['gstin'].present?
      supplier = Supplier.where(organisation: @organisation)
                         .find_by(gstin: sup_data['gstin'].upcase.strip)
      supplier_matched = supplier.present?
    end

    # 2. Normalised name match: strip all spaces + punctuation, compare case-insensitively
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

    # 3. Create new supplier
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

    # Store match status on import for UI feedback
    @supplier_matched = supplier_matched
    supplier
  end

  # Sanitise a raw material_code value from the AI.
  # Handles cases where the AI still confuses the combined Material/HSN cell
  # and puts the HSN line into material_code.
  #
  # Valid material codes are alphanumeric, often long numeric strings:
  #   "00010210210", "12601744", "5057IE24122", "67923558210"
  # HSN codes that look similar but are NOT material codes:
  #   "HSN - 320890", "HSN-320890", "320890", "32091090"
  #
  # Heuristic: if the string starts with "HSN" (case-insensitive) it is an
  # HSN line, not a material code. Pure 6-8 digit numbers are also likely
  # HSN codes (HSN codes are 4-8 digits). Material codes from paint suppliers
  # tend to be ≥9 digits or contain letters.
  HSN_PATTERN = /\AHSN[-\s]/i

  helper_method :sanitise_material_code
  def sanitise_material_code(raw)
    return nil if raw.blank?
    code = raw.to_s.strip
    # Starts with "HSN" — it's an HSN line, not a material code
    return nil if code.match?(HSN_PATTERN)
    # Pure numeric, 4–8 digits → likely an HSN code, not a material code
    return nil if code.match?(/\A\d{4,8}\z/)
    code
  end

  def parse_date(val)
    return nil if val.blank? || val.to_s == 'null'
    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end

  # Merge user-edited form params back into the stored parsed_data hash.
  # parsed_data items are stored as an Array but Rails form params turn them into
  # a Hash with string integer keys: {"0"=>{...}, "1"=>{...}}.
  # This method keeps everything as plain Hashes/Arrays so downstream code works.
  def deep_merge_params(base, incoming)
    flat = incoming.respond_to?(:to_unsafe_h) ? incoming.to_unsafe_h.deep_stringify_keys
                                               : incoming.to_h.deep_stringify_keys

    base.merge(flat) do |key, old_val, new_val|
      # Items come back as {"0"=>{...}, "1"=>{...}} — convert to Array in-place
      if key == 'items' && new_val.is_a?(Hash) && new_val.keys.all? { |k| k.to_s =~ /\A\d+\z/ }
        # Merge each indexed item back over the original array element
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