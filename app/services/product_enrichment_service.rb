# app/services/product_enrichment_service.rb
#
# Uses Groq (Llama 4 Scout) to enrich an unknown product with structured
# master data: material_code, description, HSN, GST, category etc.
#
# TEXT-ONLY call — no image needed. Same Groq key as scan invoice.
# No extra setup required — just GROQ_API_KEY in local_env.yml.
#
# Usage:
#   result = ProductEnrichmentService.call(
#     name:          "Royale Shyne Luxury Emulsion",
#     material_code: "0033",
#     brand_hint:    "Asian Paints"
#   )
#   result[:success]   # true / false
#   result[:data]      # enrichment hash
#   result[:error]     # string on failure

class ProductEnrichmentService

  GROQ_API_URL          = 'https://api.groq.com/openai/v1/chat/completions'.freeze
  GROQ_MODEL            = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze


  PROMPT_TEMPLATE = <<~PROMPT
    You are a product data assistant for an Indian paint and hardware store ERP system.

    A purchase invoice contains an item that could not be matched to the product catalogue.
    Based on the product name and code provided, return structured product master data.

    Product name from invoice: %{name}
    Material/product code hint: %{code}
    Brand hint: %{brand}

    CRITICAL: Your entire response must be ONLY the raw JSON object.
    No markdown. No code fences. No explanation before or after.
    Start your response with { and end with }. Nothing else.

    JSON structure:
    {
      "material_code": "exact product code if identifiable, else null",
      "description": "clean full product description",
      "hsn_code": "HSN/SAC code for Indian GST (4 or 8 digits), null if unknown",
      "gst_rate": 18,
      "category_guess": "e.g. Interior Emulsion / Enamel / Primer / Waterproofing / Hardware",
      "brand_guess": "brand name if identifiable",
      "pack_size_guess": "e.g. 1L / 4L / 20L / 500ml, null if not determinable",
      "confidence": 0.85,
      "notes": "any caveats or additional context"
    }

    Rules:
    - gst_rate must be one of: 0, 5, 12, 18, 28 (Indian GST slabs)
    - For paints and varnishes, HSN is typically 3208 or 3209
    - For hardware/tools, use appropriate HSN
    - confidence: 0.0 = complete guess, 1.0 = certain
    - If you cannot determine something, use null — do not fabricate
    - Return raw JSON only, starting with {
  PROMPT

  def self.call(name:, material_code: nil, brand_hint: nil, user_pref: nil)
    # user_pref kept for API compatibility but ignored — always uses Groq
    new(name: name, material_code: material_code, brand_hint: brand_hint).call
  end

  def initialize(name:, material_code: nil, brand_hint: nil)
    @name          = name.to_s.strip
    @material_code = material_code.to_s.strip.presence
    @brand_hint    = brand_hint.to_s.strip.presence
  end

  def call
    return error_result('Product name is required for enrichment') if @name.blank?

    # Always use Groq — same key as scan invoice, no extra setup needed
    call_groq
  rescue => e
    error_result("Enrichment service error: #{e.message}")
  end

  private

  def prompt
    PROMPT_TEMPLATE % {
      name:  @name,
      code:  @material_code || 'not provided',
      brand: @brand_hint    || 'unknown'
    }
  end

  # ── Groq (text-only, no image) ────────────────────────────────
  def call_groq
    api_key = ENV['GROQ_API_KEY']
    return error_result('GROQ_API_KEY not set — add GROQ_API_KEY to config/local_env.yml') if api_key.blank?

    Rails.logger.info "[ProductEnrichmentService] Calling Groq"
    Rails.logger.info "[ProductEnrichmentService]   model:  #{GROQ_MODEL}"
    Rails.logger.info "[ProductEnrichmentService]   name:   #{@name}"
    Rails.logger.info "[ProductEnrichmentService]   code:   #{@material_code}"
    Rails.logger.info "[ProductEnrichmentService]   brand:  #{@brand_hint}"

    body = {
      model:           GROQ_MODEL,
      max_tokens:      512,
      temperature:     0.1,
      response_format: { type: 'json_object' },  # Forces Groq to return valid JSON
      messages: [
        {
          role:    'system',
          content: 'You are a product data assistant. Always respond with valid JSON only. No markdown, no explanation.'
        },
        {
          role:    'user',
          content: prompt
        }
      ]
    }

    response = make_request(GROQ_API_URL, body,
                            'Authorization' => "Bearer #{api_key}")

    unless response[:success]
      Rails.logger.error "[ProductEnrichmentService] Groq FAILED: #{response[:error]}"
      return response
    end

    text = response[:raw].dig('choices', 0, 'message', 'content').to_s.strip
    Rails.logger.info "[ProductEnrichmentService] Groq response (#{text.length} chars): #{text.truncate(500)}"

    parse_enrichment(text)
  end



  # ── HTTP helper ───────────────────────────────────────────────
  def make_request(url, body, extra_headers = {})
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 15
    http.open_timeout = 8

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    extra_headers.each { |k, v| req[k] = v }
    req.body = body.to_json

    Rails.logger.info "[ProductEnrichmentService] POST #{url}"
    Rails.logger.info "[ProductEnrichmentService] Request body (truncated): #{req.body.truncate(400)}"

    res = http.request(req)
    Rails.logger.info "[ProductEnrichmentService] Response status: #{res.code}"

    unless res.code.to_i.between?(200, 299)
      return error_result("API returned #{res.code}: #{res.body[0..200]}")
    end

    { success: true, raw: JSON.parse(res.body) }
  rescue JSON::ParserError => e
    error_result("Invalid JSON from API: #{e.message}")
  rescue Net::ReadTimeout, Net::OpenTimeout
    error_result('API request timed out')
  end

  # ── Parse and validate the AI response ───────────────────────
  def parse_enrichment(text)
    json_text = extract_json(text)
    return error_result("AI returned no JSON. Raw response: #{text.truncate(200)}") unless json_text

    data = JSON.parse(json_text)

    gst        = data['gst_rate'].to_f
    gst        = 18.0 unless [0, 5, 12, 18, 28].include?(gst.to_i)
    confidence = [[data['confidence'].to_f, 0.0].max, 1.0].min.round(2)

    enriched = {
      'material_code'   => presence_str(data['material_code']),
      'description'     => presence_str(data['description']),
      'hsn_code'        => presence_str(data['hsn_code']),
      'gst_rate'        => gst,
      'category_guess'  => presence_str(data['category_guess']),
      'brand_guess'     => presence_str(data['brand_guess']),
      'pack_size_guess' => presence_str(data['pack_size_guess']),
      'confidence'      => confidence,
      'notes'           => presence_str(data['notes'])
    }

    { success: true, data: enriched }
  rescue JSON::ParserError => e
    error_result("JSON parse failed: #{e.message}. Raw: #{text.truncate(300)}")
  end

  # Robustly extract a JSON object from AI response text.
  # Handles: plain JSON, markdown fences, preamble text, trailing commentary.
  def extract_json(text)
    return nil if text.blank?

    # Strategy 1: text is already valid JSON
    begin
      JSON.parse(text)
      return text
    rescue JSON::ParserError
      # continue to next strategy
    end

    # Strategy 2: extract from ```json ... ``` or ``` ... ``` fence
    if (m = text.match(/```(?:json)?\s*(\{.*?\})\s*```/m))
      return m[1].strip
    end

    # Strategy 3: find first { to last } — strips preamble/postamble
    first_brace = text.index('{')
    last_brace  = text.rindex('}')
    if first_brace && last_brace && last_brace > first_brace
      candidate = text[first_brace..last_brace]
      begin
        JSON.parse(candidate)
        return candidate
      rescue JSON::ParserError
        # couldn't extract valid JSON
      end
    end

    nil
  end

  def presence_str(val)
    val.to_s.strip.presence
  end

  def error_result(msg)
    { success: false, data: nil, error: msg }
  end

end