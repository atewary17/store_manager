# app/services/groq_invoice_parser.rb
#
# Sends a purchase invoice IMAGE to Groq (Llama 4 Scout vision model) and
# returns a structured Ruby hash matching the same shape as GeminiInvoiceParser.
#
# FREE TIER: ~14,400 req/day, no credit card needed.
# Get key: https://console.groq.com → API Keys
#
# LIMITATION: Groq vision only accepts images (JPG/PNG/WEBP), NOT PDFs.
# PDFs are auto-converted to a JPEG of page 1 using pdftoppm (no extra gems).
# Install: brew install poppler  (Mac) / apt install poppler-utils (Linux)
#
# Usage:
#   result = GroqInvoiceParser.call(base64_data: "...", mime_type: "image/jpeg")
#   result[:success]   # true/false
#   result[:data]      # parsed hash
#   result[:error]     # error string on failure
#
class GroqInvoiceParser
  GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'.freeze
  GROQ_MODEL   = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze

  # Same prompt as Gemini — just JSON output requested
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
        "amount_in_words": "..."
      },
      "items": [
        {
          "sr_no": 1,
          "material_code": "...",
          "description": "...",
          "hsn_code": "...",
          "pack_size": "...",
          "num_packs": 0,
          "quantity": 0.000,
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
    - pack_size: e.g. "900 ML", "3.6 LT", "1 LTR"
    - quantity: total volume/weight (num_packs × pack_size volume)
    - unit_rate: rate per unit of volume. If not shown, calculate it.
    - hsn_code: digits only, no slashes or "HSN" prefix. e.g. "320890" not "HSN - 320890"
    - If a field is genuinely absent, use null for strings and 0 for numbers.
    - Do not invent data. Extract only what is visible.
  PROMPT

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

    # Groq vision only supports images — convert PDF to JPEG if needed
    image_base64, image_mime = prepare_image

    body = build_request_body(image_base64, image_mime)
    response = make_request(body)
    parse_response(response)

  rescue => e
    { success: false, error: e.message, data: nil, raw_response: nil, provider: 'groq' }
  end

  private

  # ── Image preparation ─────────────────────────────────────────────────────

  def prepare_image
    if @mime_type == 'application/pdf'
      pdf_to_jpeg
    else
      # Already an image — pass through
      [@base64_data, @mime_type]
    end
  end

  def pdf_to_jpeg
    # Uses pdftoppm from poppler — no extra gems, no ImageMagick.
    # Mac:   brew install poppler
    # Linux: apt install poppler-utils  (already on Render)
    pdftoppm_bin = `which pdftoppm`.strip
    raise "pdftoppm not found. Install with: brew install poppler" if pdftoppm_bin.empty?

    tmp_pdf = Tempfile.new(['invoice', '.pdf'])
    tmp_dir = Dir.mktmpdir('invoice_pages')

    begin
      tmp_pdf.binmode
      tmp_pdf.write(Base64.decode64(@base64_data))
      tmp_pdf.flush

      # Convert first page only at 200 DPI → JPEG
      out_prefix = File.join(tmp_dir, 'page')
      system(pdftoppm_bin, '-jpeg', '-r', '200', '-f', '1', '-l', '1',
             tmp_pdf.path, out_prefix)

      pages = Dir.glob("#{tmp_dir}/*.jpg").sort
      raise 'PDF conversion produced no pages — is the file a valid PDF?' if pages.empty?

      jpeg_data = Base64.strict_encode64(File.binread(pages.first))
      [jpeg_data, 'image/jpeg']
    ensure
      tmp_pdf.close
      tmp_pdf.unlink
      FileUtils.rm_rf(tmp_dir)
    end
  end

  # ── Request ───────────────────────────────────────────────────────────────

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
              image_url: {
                url: "data:#{image_mime};base64,#{image_base64}"
              }
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
    http.verify_mode  = OpenSSL::SSL::VERIFY_NONE  # Mac/Windows CRL issue

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type']  = 'application/json'
    req['Authorization'] = "Bearer #{@api_key}"
    req.body = body.to_json

    http.request(req)
  end

  # ── Response ──────────────────────────────────────────────────────────────

  def parse_response(response)
    unless response.code.to_i == 200
      return {
        success:      false,
        error:        "Groq API returned HTTP #{response.code}: #{response.body}",
        data:         nil,
        raw_response: response.body,
        provider:     'groq'
      }
    end

    outer = JSON.parse(response.body)
    text  = outer.dig('choices', 0, 'message', 'content').to_s.strip

    # Strip markdown fences if model wraps output
    text = text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip

    data = JSON.parse(text)

    {
      success:      true,
      data:         data,
      raw_response: text,
      error:        nil,
      provider:     'groq'
    }

  rescue JSON::ParserError => e
    {
      success:      false,
      error:        "JSON parse failed: #{e.message}",
      data:         nil,
      raw_response: text,
      provider:     'groq'
    }
  end
end