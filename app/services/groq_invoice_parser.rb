# app/services/groq_invoice_parser.rb
#
# Sends purchase invoice pages to Groq (Llama 4 Scout vision) and returns a
# structured Ruby hash.
#
# PDF FLOW  : all pages converted to JPEG via pdftoppm, one Groq call per page,
#             results merged — header + supplier from page 1, items from all pages.
# IMAGE FLOW: single image sent directly; supports JPG, PNG, WEBP.
#
# FREE TIER : ~14,400 req/day (no credit card).
# Install   : brew install poppler  (Mac) / apt install poppler-utils (Linux)
#
class GroqInvoiceParser
  GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'.freeze
  GROQ_MODEL   = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze

  # ── Prompt injected for every page ────────────────────────────────────────
  PROMPT = <<~PROMPT.freeze
    You are an expert at reading Indian B2B purchase invoices for paint/hardware distributors.

    Extract all data from this invoice image and return ONLY a valid JSON object — no markdown,
    no explanation, no code fences. Just the raw JSON.

    The JSON must have exactly this structure:

    {
      "supplier": {
        "name": "...",
        "gstin": "...",
        "pan": "...",
        "state": "...",
        "state_code": "...",
        "address": "..."
      },
      "header": {
        "invoice_number": "...",
        "invoice_date": "YYYY-MM-DD",
        "delivery_date": "YYYY-MM-DD or null",
        "delivery_number": "...",
        "po_reference": "...",
        "place_of_supply": "...",
        "irn": "...",
        "eway_bill": "...",
        "lr_number": "...",
        "transporter": "...",
        "vehicle_number": "...",
        "total_taxable_amount": 0.00,
        "total_cgst": 0.00,
        "total_sgst": 0.00,
        "total_igst": 0.00,
        "cash_discount_amount": 0.00,
        "cash_discount_percent": 0.00,
        "total_amount": 0.00,
        "amount_in_words": "...",
        "page_number": 1,
        "total_pages": 1
      },
      "items": [
        {
          "sr_no": 1,
          "material_code": "...",
          "description": "...",
          "hsn_code": "...",
          "pack_size": "...",
          "num_packs": 0,
          "quantity": 0,
          "volume": 0.000,
          "unit": "...",
          "rate_per_pack": 0.00,
          "unit_rate": 0.00,
          "value": 0.00,
          "discount_percent": 0.00,
          "discount_amount": 0.00,
          "taxable_amount": 0.00,
          "cgst_percent": 0.00,
          "cgst_amount": 0.00,
          "sgst_percent": 0.00,
          "sgst_amount": 0.00,
          "igst_percent": 0.00,
          "igst_amount": 0.00,
          "total_amount": 0.00
        }
      ]
    }

    Rules:
    - Dates must be YYYY-MM-DD. If a date is missing, use null.
    - All numeric fields must be numbers (not strings). If missing, use 0.
    - page_number: the current page number as printed on this page (e.g. "Page 1 of 3" → 1).
    - total_pages: the total number of pages as printed (e.g. "Page 1 of 3" → 3). If not visible, use 1.
    - material_code: the supplier's internal product/material code.
      IMPORTANT: Many invoices (especially Asian Paints) have a combined "Material / HSN" column
      where a single cell contains TWO values stacked vertically:
        Line 1: the material code  (e.g. "00010210210", "5057IE24122", "67923558210")
        Line 2: "HSN - 320890" or "HSN-320890" (the HSN code, prefixed with "HSN")
      In this case: material_code = the FIRST line (numeric/alphanumeric code WITHOUT "HSN")
                    hsn_code      = digits only from the SECOND line (e.g. "320890")
      Never put an HSN value into material_code. If the only value in the cell starts with
      "HSN", the material_code is missing — set it to null.
      Examples of valid material codes: "12601744", "00010210210", "5057IE24122", "67923558210"
      Examples of what is NOT a material code: "HSN - 320890", "32091090", "321390"
    - description: the full product name exactly as written
    - pack_size: the size of one individual unit, e.g. "1 LT", "10 LT", "900 ML"
    - num_packs: the count of cartons/drums/boxes. For Asian Paints invoices this is the numeric
      part of the "Packs" column (e.g. "1 CAR" → 1, "2 DRM" → 2). If no Packs column, use the
      Qty column value.
    - quantity: the INTEGER value from the "Qty" or "Quantity" column — the count of individual
      units ordered (cans, litres, pieces).
      CRITICAL — Asian Paints invoice column order: (1) Material/HSN, (2) Description,
      (3) Qty ← USE THIS FOR quantity, (4) Packs → num_packs, (5) Volume/Kg/Lt/M → volume.
      NEVER use the Volume column value as quantity. quantity must be an integer.
    - volume: the value from the "Volume", "Kg/Lt/M", or total weight/volume column.
      For Asian Paints invoices this is the 5th column (e.g. 6.000, 20.000, 40.000).
      If no such column exists, use 0.
    - unit: the unit of measurement for the quantity field.
      For Asian Paints invoices: always use "UNT" (individual units/pieces — cans, drums, etc.).
      Do NOT use "LT", "KG" or any volume unit here; those belong in the volume field.
      For other suppliers: extract the unit exactly as written on the invoice.
    - discount_amount: the per-line cash discount in rupees. Asian Paints invoices have a
      "Cash Disc." column (column 9); values appear with a trailing "-" (e.g. "83.70-") —
      store as a positive number (83.70). Do NOT confuse with "In-Bill Disc." columns which
      are separate. If no cash discount on the line, use 0.
    - discount_percent: use only when the invoice states a percentage discount on the line.
      If only a rupee discount_amount is shown, set discount_percent to 0.
    - cash_discount_amount (header): the total fast/cash discount shown in the invoice summary
      section, e.g. "Fast Cash Discount: 2119.50-" → 2119.50. This often appears only on the
      last page. If not visible on this page, use 0.
    - unit_rate: rate per individual unit. If not shown, calculate it from value / quantity.
    - hsn_code: digits only, no slashes or "HSN" prefix. e.g. "320890" not "HSN - 320890"
    - If this page contains no line items (e.g. it is a terms/signature/acknowledgement page),
      return an empty items array [].
    - If a field is genuinely absent, use null for strings and 0 for numbers.
    - Do not invent data. Extract only what is visible.
  PROMPT

  # ── Public entry point ─────────────────────────────────────────────────────
  #
  # Returns:
  #   {
  #     success: true/false,
  #     data:    { supplier:, header:, items:, _meta: { pages_scanned:, page_count:, pages_data: } },
  #     error:   "...",
  #     raw_response: "...",
  #     provider: 'groq',
  #     preview_image: "<base64 jpeg of page 1>"   # nil for plain images
  #   }
  #
  def self.call(base64_data:, mime_type:)
    new(base64_data: base64_data, mime_type: mime_type).call
  end

  def initialize(base64_data:, mime_type:)
    @base64_data = base64_data
    @mime_type   = mime_type
    @api_key     = ENV['GROQ_API_KEY']
  end

  def call
    raise 'GROQ_API_KEY not set' unless @api_key.present?

    pages, preview_image = prepare_pages

    page_results = pages.each_with_index.map do |(page_b64, page_mime), idx|
      parse_single_page(page_b64, page_mime, idx + 1)
    end

    merged = merge_page_results(page_results)
    merged.merge(preview_image: preview_image, provider: 'groq')

  rescue => e
    { success: false, error: e.message, data: nil, raw_response: nil,
      preview_image: nil, provider: 'groq' }
  end

  private

  # ── Page preparation ───────────────────────────────────────────────────────

  # Returns [ [[base64, mime], ...], preview_base64 ]
  def prepare_pages
    if @mime_type == 'application/pdf'
      pages = pdf_to_all_jpegs
      preview = pages.first&.first
      [pages, preview]
    else
      [[ [@base64_data, @mime_type] ], nil]
    end
  end

  # Convert every PDF page to a JPEG.  Returns [[base64, 'image/jpeg'], ...]
  def pdf_to_all_jpegs
    pdftoppm_bin = `which pdftoppm`.strip
    raise 'pdftoppm not found. Install: brew install poppler (Mac) / apt install poppler-utils (Linux)' if pdftoppm_bin.empty?

    tmp_pdf = Tempfile.new(['invoice', '.pdf'])
    tmp_dir = Dir.mktmpdir('invoice_pages')

    begin
      tmp_pdf.binmode
      tmp_pdf.write(Base64.decode64(@base64_data))
      tmp_pdf.flush

      out_prefix = File.join(tmp_dir, 'page')
      # 300 DPI gives the AI clearer column separation, reducing Qty/Volume confusion
      system(pdftoppm_bin, '-jpeg', '-r', '300', tmp_pdf.path, out_prefix)

      pages = Dir.glob("#{tmp_dir}/*.jpg").sort
      raise 'PDF conversion produced no pages — is this a valid PDF?' if pages.empty?

      pages.map { |path| [Base64.strict_encode64(File.binread(path)), 'image/jpeg'] }
    ensure
      tmp_pdf.close
      tmp_pdf.unlink
      FileUtils.rm_rf(tmp_dir)
    end
  end

  # ── Single-page AI call ────────────────────────────────────────────────────

  def parse_single_page(base64, mime, page_num)
    body     = build_request_body(base64, mime)
    response = make_request(body)
    result   = parse_response(response)
    result.merge(page_num: page_num)
  rescue => e
    { success: false, error: "Page #{page_num}: #{e.message}", data: nil,
      raw_response: nil, page_num: page_num }
  end

  # ── Merge results from all pages ───────────────────────────────────────────

  def merge_page_results(results)
    successful = results.select { |r| r[:success] && r[:data].present? }

    if successful.empty?
      first_error = results.first
      return {
        success:      false,
        error:        results.map { |r| r[:error] }.compact.join(' | '),
        data:         nil,
        raw_response: first_error&.dig(:raw_response)
      }
    end

    # Header + supplier from page 1 (most complete)
    base       = successful.first[:data]
    all_items  = successful.flat_map { |r| r[:data]['items'] || [] }

    # Post-parse correction: when quantity == volume the AI read the wrong column.
    # Substitute num_packs (the integer pack count) as the corrected quantity.
    all_items.each do |item|
      qty    = item['quantity'].to_f
      volume = item['volume'].to_f
      next unless volume > 0 && (qty - volume).abs < 0.01
      # num_packs is the carton/drum count — the true ordered unit count
      np = item['num_packs'].to_i
      item['quantity']    = np > 0 ? np : item['quantity']
      item['_qty_fixed']  = true   # flag so UI can still warn if needed
    end

    # Determine true page_count from AI — take the max total_pages seen
    ai_total_pages = successful.map { |r| r[:data].dig('header', 'total_pages').to_i }.max
    pages_scanned  = successful.size

    merged_data = base.merge(
      'items'  => all_items,
      '_meta'  => {
        'pages_scanned' => pages_scanned,
        'page_count'    => [ai_total_pages, pages_scanned].max,
        'pages_data'    => successful.map { |r|
          {
            'page_num'   => r[:page_num],
            'item_count' => (r[:data]['items'] || []).size,
            'page_number'  => r[:data].dig('header', 'page_number'),
            'total_pages'  => r[:data].dig('header', 'total_pages')
          }
        }
      }
    )

    {
      success:      true,
      data:         merged_data,
      raw_response: successful.map { |r| r[:raw_response] }.join("\n---page---\n"),
      error:        nil
    }
  end

  # ── HTTP request ───────────────────────────────────────────────────────────

  def build_request_body(image_base64, image_mime)
    {
      model:       GROQ_MODEL,
      temperature: 0.1,
      max_tokens:  8192,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: PROMPT },
            {
              type: 'image_url',
              image_url: { url: "data:#{image_mime};base64,#{image_base64}" }
            }
          ]
        }
      ]
    }
  end

  def make_request(body)
    uri  = URI.parse(GROQ_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 120
    http.verify_mode  = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type']  = 'application/json'
    req['Authorization'] = "Bearer #{@api_key}"
    req.body = body.to_json

    http.request(req)
  end

  def parse_response(response)
    unless response.code.to_i == 200
      return {
        success:      false,
        error:        "Groq API returned HTTP #{response.code}: #{response.body}",
        data:         nil,
        raw_response: response.body
      }
    end

    outer = JSON.parse(response.body)
    text  = outer.dig('choices', 0, 'message', 'content').to_s.strip
    text  = text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip

    data = JSON.parse(text)

    { success: true, data: data, raw_response: text, error: nil }

  rescue JSON::ParserError => e
    { success: false, error: "JSON parse failed: #{e.message}", data: nil, raw_response: text }
  end
end
