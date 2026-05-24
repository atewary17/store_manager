module InvoiceScan
  class AiParser
    GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'.freeze
    GROQ_MODEL   = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze

    def self.call(ocr_text:, supplier_hint: nil, page_num: 1)
      new.call(ocr_text: ocr_text, supplier_hint: supplier_hint, page_num: page_num)
    end

    def call(ocr_text:, supplier_hint: nil, page_num: 1)
      api_key = ENV['GROQ_API_KEY']
      raise 'GROQ_API_KEY not set' unless api_key.present?

      body = {
        model:       GROQ_MODEL,
        temperature: 0.1,
        max_tokens:  8192,
        messages: [ { role: 'user', content: build_prompt(ocr_text, supplier_hint) } ]
      }.to_json

      uri  = URI.parse(GROQ_API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = 10
      http.read_timeout = 120
      http.verify_mode  = OpenSSL::SSL::VERIFY_NONE

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type']  = 'application/json'
      req['Authorization'] = "Bearer #{api_key}"
      req.body = body

      res  = http.request(req)
      code = res.code.to_i

      unless code == 200
        return { success: false, data: nil, http_status: code,
                 error: "Groq HTTP #{code}: #{res.body.to_s.truncate(300)}",
                 raw_response: res.body }
      end

      outer    = JSON.parse(res.body)
      raw_text = outer.dig('choices', 0, 'message', 'content').to_s.strip
      json_str = raw_text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
      data     = JSON.parse(json_str)

      { success: true, data: data, raw_response: raw_text, error: nil, http_status: 200 }

    rescue JSON::ParserError => e
      { success: false, data: nil, error: "AI JSON parse failed: #{e.message}",
        raw_response: raw_text.to_s, http_status: nil }
    rescue Net::OpenTimeout
      { success: false, data: nil, error: 'AI parse connection timeout (10s)',
        raw_response: nil, http_status: 408 }
    rescue Net::ReadTimeout
      { success: false, data: nil, error: 'AI parse read timeout (120s)',
        raw_response: nil, http_status: 408 }
    rescue => e
      { success: false, data: nil, error: "AI parse error: #{e.class} — #{e.message}",
        raw_response: nil, http_status: nil }
    end

    private

    def build_prompt(ocr_text, supplier_hint)
      instructions = PromptLoader.for_supplier(supplier_hint)
      "#{instructions}\n\nHere is the OCR-extracted text from the invoice. Parse it and return the JSON:\n\n#{ocr_text}"
    end
  end
end
