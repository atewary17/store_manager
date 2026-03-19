# app/services/gemini_invoice_parser.rb
#
# Sends a purchase invoice (image or PDF) to Google Gemini Flash
# and returns a structured Ruby hash.
#
# Usage:
#   result = GeminiInvoiceParser.call(base64_data: "...", mime_type: "application/pdf")
#   result[:success]       # true / false
#   result[:data]          # parsed hash (see PROMPT for shape)
#   result[:raw_response]  # raw JSON string from Gemini
#   result[:error]         # error message if failed
#
class GeminiInvoiceParser

  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent".freeze

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
    - pack_size: e.g. "900 ML", "3.6 LT", "18.0", "1 LTR", "50 ML"
    - quantity: total volume/weight (num_packs × pack_size volume). e.g. if 4 packs of 3.6 LT → quantity = 14.400
    - unit: e.g. "LT", "ML", "KG", "PCS", "EA"
    - unit_rate: rate per unit of volume (total_amount / quantity). If not shown, calculate it.
    - For invoices with a single cash_discount applied to the whole invoice (not per line),
      put it in header.cash_discount_amount and set item-level discount_amount to 0.
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
    @api_key     = ENV['GEMINI_API_KEY']
  end

  def call
    raise "GEMINI_API_KEY not set" unless @api_key.present?

    url  = "#{GEMINI_API_URL}?key=#{@api_key}"
    body = build_request_body

    response = make_request(url, body)
    parse_response(response)

  rescue => e
    { success: false, error: e.message, data: nil, raw_response: nil }
  end

  def mock_response
    Rails.logger.info "[GeminiInvoiceParser] MOCK MODE — returning fake data"
    {
      success:      true,
      raw_response: '(mock)',
      error:        nil,
      data: {
        'supplier' => {
          'name'    => 'Mock Supplier Pvt Ltd',
          'gstin'   => '29AABCU9603R1ZX',
          'address' => '123 Test Street, Bengaluru'
        },
        'invoice' => {
          'invoice_number' => 'MOCK-001',
          'invoice_date'   => Date.today.iso8601,
          'due_date'       => (Date.today + 30).iso8601,
          'subtotal'       => 10000.0,
          'gst_total'      => 1800.0,
          'grand_total'    => 11800.0
        },
        'items' => [
          {
            'description'   => 'Mock Paint 4L White',
            'material_code' => 'MOCK-SKU-01',
            'hsn'           => '3208',
            'qty'           => 10,
            'unit'          => 'Can',
            'rate'          => 590.0,
            'gst_percent'   => 18.0,
            'taxable_amount'=> 5900.0,
            'total'         => 6962.0
          },
          {
            'description'   => 'Mock Primer 1L',
            'material_code' => 'MOCK-SKU-02',
            'hsn'           => '3208',
            'qty'           => 5,
            'unit'          => 'Can',
            'rate'          => 350.0,
            'gst_percent'   => 18.0,
            'taxable_amount'=> 1750.0,
            'total'         => 2065.0
          }
        ]
      }
    }
  end

  private

  def build_request_body
    {
      contents: [
        {
          parts: [
            { text: PROMPT },
            {
              inline_data: {
                mime_type: @mime_type,
                data:      @base64_data
              }
            }
          ]
        }
      ],
      generationConfig: {
        temperature:     0.1,   # low temp for deterministic extraction
        maxOutputTokens: 8192
      }
    }
  end

  def make_request(url, body)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 120  # Gemini can be slow on large PDFs

    # Ruby's OpenSSL on Mac/Windows sometimes can't verify Google's CRL chain.
    # We still use SSL (encrypted), we just skip the CRL revocation check.
    # On Render (Linux) the system CA bundle handles this correctly regardless.
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req.body = body.to_json

    http.request(req)
  end

  def parse_response(response)
    unless response.code.to_i == 200
      return {
        success: false,
        error: "Gemini API returned HTTP #{response.code}: #{response.body}",
        data: nil,
        raw_response: response.body
      }
    end

    outer = JSON.parse(response.body)
    text  = outer.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.strip

    # Strip markdown code fences if Gemini wraps in ```json ... ```
    text = text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip

    data = JSON.parse(text)

    {
      success:      true,
      data:         data,
      raw_response: text,
      error:        nil
    }

  rescue JSON::ParserError => e
    {
      success:      false,
      error:        "JSON parse failed: #{e.message}",
      data:         nil,
      raw_response: text
    }
  end
end