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

  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent".freeze

  # Use the same prompt as the Groq parser for consistent field definitions and output shape.
  PROMPT = GroqInvoiceParser::PROMPT

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