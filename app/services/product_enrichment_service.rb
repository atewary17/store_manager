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
  GROQ_MODEL            = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze  # supports json_object mode
  GROQ_MODEL_FALLBACK   = 'llama3-8b-8192'.freeze  # fallback if scout unavailable


  # Prompt is built dynamically (not a template constant) so it can include
  # live brand and category lists from the database. See #prompt method below.

  def self.call(name:, material_code: nil, brand_hint: nil, user_pref: nil)
    # Load brand and category lists from DB so prompt can reference exact names
    brand_list    = Brand.active.ordered.pluck(:name)
    category_list = ProductCategory.active.ordered.pluck(:name)
    new(
      name:          name,
      material_code: material_code,
      brand_hint:    brand_hint,
      brand_list:    brand_list,
      category_list: category_list
    ).call
  end

  def initialize(name:, material_code: nil, brand_hint: nil,
                 brand_list: [], category_list: [])
    @name          = name.to_s.strip
    @material_code = material_code.to_s.strip.presence
    @brand_hint    = brand_hint.to_s.strip.presence
    @brand_list    = brand_list
    @category_list = category_list
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
    brand_options    = @brand_list.any?    ? @brand_list.join(', ')    : 'not available'
    category_options = @category_list.any? ? @category_list.join(', ') : 'not available'

    <<~PROMPT
      You are a product data assistant for an Indian paint and hardware store ERP system.

      A purchase invoice contains an item that could not be matched to the product catalogue.
      Your job is to identify the product and return structured data so it can be saved.

      Product name from invoice: #{@name}
      Material/product code:     #{@material_code || 'not provided'}
      Brand hint from invoice:   #{@brand_hint || 'not provided'}

      IMPORTANT — You must pick brand_guess and category_guess ONLY from these exact lists:

      Available brands (use the EXACT spelling from this list):
      #{brand_options}

      Available categories (use the EXACT spelling from this list):
      #{category_options}

      If the brand is not in the list, set brand_guess to null.
      If the category is not in the list, set category_guess to null.
      Do NOT invent or abbreviate — use the exact name from the list above.

      For example: if the product is "Asian Paints Apcolite Enamel" and "Asian Paints"
      is in the brand list, return "brand_guess": "Asian Paints" — not "AP" or "AsianPaints".

      CRITICAL: Your entire response must be ONLY the raw JSON object.
      No markdown. No code fences. No explanation. Start with { and end with }.

      JSON structure:
      {
        "material_code": "product code if identifiable, else null",
        "description": "clean full product description",
        "hsn_code": "HSN code (4 or 8 digits), null if unknown",
        "gst_rate": 18,
        "category_guess": "MUST be exact name from the category list above, or null",
        "brand_guess": "MUST be exact name from the brand list above, or null",
        "pack_size_guess": "e.g. 1L / 4L / 200ml, null if unknown",
        "confidence": 0.85,
        "notes": "brief reason for your choices"
      }

      Rules:
      - gst_rate must be one of: 0, 5, 12, 18, 28
      - For paints/varnishes HSN is typically 3208 or 3209
      - confidence: 0.0 = complete guess, 1.0 = certain
      - If you cannot determine something, use null
    PROMPT
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

    # Detect if model returned conversational text instead of JSON
    if text.strip.start_with?('{')
      Rails.logger.info "[ProductEnrichmentService] Response is JSON — parsing directly"
    else
      Rails.logger.warn "[ProductEnrichmentService] Response is conversational text — will use fallback parser"
      Rails.logger.warn "[ProductEnrichmentService] HINT: Check your local model name. Should be 'meta-llama/llama-4-scout-17b-16e-instruct'"
    end

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
  # Strategy 1: text IS valid JSON
  # Strategy 2: extract from ```json ... ``` fence
  # Strategy 3: find first { to last }
  # Strategy 4: parse conversational response (when model ignores json_object mode)
  def extract_json(text)
    return nil if text.blank?

    # Strategy 1: already valid JSON
    begin
      JSON.parse(text)
      return text
    rescue JSON::ParserError; end

    # Strategy 2: markdown fence
    if (m = text.match(/```(?:json)?\s*(\{.*?\})\s*```/m))
      begin
        JSON.parse(m[1].strip)
        return m[1].strip
      rescue JSON::ParserError; end
    end

    # Strategy 3: first { to last }
    first_brace = text.index('{')
    last_brace  = text.rindex('}')
    if first_brace && last_brace && last_brace > first_brace
      candidate = text[first_brace..last_brace]
      begin
        JSON.parse(candidate)
        return candidate
      rescue JSON::ParserError; end
    end

    # Strategy 4: conversational response parser
    # Handles when the model returns prose instead of JSON
    result = parse_conversational_response(text)
    result ? result.to_json : nil
  end

  # Parses a conversational AI response and extracts product fields.
  # Uses pattern matching on common phrases the model uses when explaining.
  def parse_conversational_response(text)
    return nil if text.blank?

    extracted = {}

    # ── Brand ─────────────────────────────────────────────────
    # "Brand Hint: Asian Paints", "brand: Asian Paints", "brand is Asian Paints"
    if (m = text.match(/brand[^:]*[:–\-]\s*["\*]*([\w\s&]+?)["*
,\.]/i))
      extracted['brand_guess'] = m[1].strip
    end
    # Also look for known brands in the text directly
    @brand_list.each do |brand|
      if text.include?(brand)
        extracted['brand_guess'] = brand
        break
      end
    end

    # ── Category ──────────────────────────────────────────────
    @category_list.each do |cat|
      if text.downcase.include?(cat.downcase)
        extracted['category_guess'] = cat
        break
      end
    end
    # Fallback: look for paint category keywords
    if extracted['category_guess'].nil?
      case text.downcase
      when /enamel/           then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('enamel') }
      when /emulsion/         then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('emulsion') }
      when /primer/           then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('primer') }
      when /waterproof/       then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('waterproof') }
      when /distemper/        then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('distemper') }
      when /wood\s*(finish)?/ then extracted['category_guess'] = @category_list.find { |c| c.downcase.include?('wood') }
      end
    end

    # ── Pack size ─────────────────────────────────────────────
    if (m = text.match(/(\d+(?:\.\d+)?)\s*(ml|l|ltr|litre|kg|kgs|g|pcs|nos)/i))
      extracted['pack_size_guess'] = "#{m[1]}#{m[2]}"
    end

    # ── HSN code ──────────────────────────────────────────────
    if (m = text.match(/hsn[^:]*[:–\-]\s*["*]*(\d{4,8})/i))
      extracted['hsn_code'] = m[1]
    elsif text.match?(/paint|enamel|emulsion|varnish/i)
      extracted['hsn_code'] = '3209'
    end

    # ── Material code ─────────────────────────────────────────
    extracted['material_code'] = @material_code if @material_code.present?

    # ── Description ───────────────────────────────────────────
    extracted['description'] = @name  # use original name as base

    # ── GST ───────────────────────────────────────────────────
    extracted['gst_rate']   = 18  # default for paints
    extracted['confidence'] = 0.5  # lower confidence for parsed response
    extracted['notes']      = 'Parsed from conversational AI response — verify details'

    Rails.logger.info "[ProductEnrichmentService] Parsed conversational response: #{extracted.inspect}"

    extracted.any? ? extracted : nil
  end

  def presence_str(val)
    val.to_s.strip.presence
  end

  def error_result(msg)
    { success: false, data: nil, error: msg }
  end

end