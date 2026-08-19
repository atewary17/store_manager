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

  # Vision models, tried in order. The free tier load-sheds individual models with
  # HTTP 503 ("overloaded") unpredictably — a model that 503s now may be fine in a
  # minute, and vice-versa — so we fall back through a chain rather than pinning one.
  # Order = fastest/healthiest first. gemini-flash-lite-latest returns a full invoice
  # extraction in ~6s; the heavier flash aliases are backups. Override with a
  # comma-separated GEMINI_MODEL list to change or shorten the chain.
  GEMINI_MODELS = (
    ENV['GEMINI_MODEL'].presence&.split(',')&.map(&:strip).presence ||
    %w[gemini-flash-lite-latest gemini-3.5-flash gemini-flash-latest]
  ).freeze

  def self.api_url_for(model)
    "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"
  end

  # Transient, server-side statuses worth retrying (overload / rate / gateway).
  RETRYABLE_STATUS = [429, 500, 502, 503, 504].freeze
  MAX_ATTEMPTS     = 2

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

    body = build_request_body
    last_error = nil

    # Walk the model chain: on a transient/overload failure (503 etc.) or timeout,
    # fall through to the next model instead of failing the whole scan.
    GEMINI_MODELS.each do |model|
      url = "#{self.class.api_url_for(model)}?key=#{@api_key}"
      begin
        response = make_request(url, body)
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        last_error = "#{model}: #{e.class}"
        Rails.logger.warn "[GeminiInvoiceParser] #{model} timed out — trying next model"
        next
      end

      if RETRYABLE_STATUS.include?(response.code.to_i)
        last_error = "#{model}: HTTP #{response.code}"
        Rails.logger.warn "[GeminiInvoiceParser] #{model} returned #{response.code} — trying next model"
        next
      end

      result = parse_response(response)
      result[:model] = model if result.is_a?(Hash)
      return result
    end

    { success: false, error: "All Gemini models unavailable (#{last_error})",
      data: nil, raw_response: nil }

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

  # Generic invoice-scan prompt (same one Groq uses when no supplier is known).
  def prompt
    InvoiceScan::PromptLoader.for_supplier(nil)
  end

  def build_request_body
    {
      contents: [
        {
          parts: [
            { text: prompt },
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
    http.read_timeout = 75   # if a model hangs, fail over to the next one rather than wait forever
    http.open_timeout = 15

    # Ruby's OpenSSL on Mac/Windows sometimes can't verify Google's CRL chain.
    # We still use SSL (encrypted), we just skip the CRL revocation check.
    # On Render (Linux) the system CA bundle handles this correctly regardless.
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req.body = body.to_json

    # Gemini can return 503 (overloaded) / 429 (rate) on demand spikes. Retry
    # those transient errors with exponential backoff (2s, 4s, 8s) before failing.
    attempt = 0
    loop do
      attempt += 1
      response = http.request(req)
      return response if !RETRYABLE_STATUS.include?(response.code.to_i) || attempt >= MAX_ATTEMPTS

      wait = 2**attempt
      Rails.logger.warn "[GeminiInvoiceParser] HTTP #{response.code} (attempt #{attempt}/#{MAX_ATTEMPTS}); retrying in #{wait}s"
      sleep(wait)
    end
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