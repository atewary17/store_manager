module InvoiceScan
  class OcrClient
    API_URL = 'https://vision.googleapis.com/v1/images:annotate'.freeze

    def self.call(base64_data:)
      new.call(base64_data: base64_data)
    end

    def call(base64_data:)
      api_key = ENV['GOOGLE_VISION_API_KEY']
      raise 'GOOGLE_VISION_API_KEY not set' unless api_key.present?

      body = {
        requests: [
          {
            image:    { content: base64_data },
            features: [{ type: 'DOCUMENT_TEXT_DETECTION' }]
          }
        ]
      }.to_json

      uri  = URI.parse("#{API_URL}?key=#{api_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = 10
      http.read_timeout = 30
      http.verify_mode  = OpenSSL::SSL::VERIFY_NONE

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req.body = body

      res  = http.request(req)
      code = res.code.to_i

      unless code == 200
        return { success: false, text: '', http_status: code,
                 error: "Google Vision HTTP #{code}: #{res.body.to_s.truncate(300)}",
                 raw_response: res.body }
      end

      parsed = JSON.parse(res.body)
      text   = parsed.dig('responses', 0, 'fullTextAnnotation', 'text').to_s

      { success: true, text: text, raw_response: res.body, http_status: code, error: nil }

    rescue Net::OpenTimeout
      { success: false, text: '', error: 'OCR connection timeout (10s)',
        raw_response: nil, http_status: 408 }
    rescue Net::ReadTimeout
      { success: false, text: '', error: 'OCR read timeout (30s)',
        raw_response: nil, http_status: 408 }
    rescue => e
      { success: false, text: '', error: "OCR error: #{e.class} — #{e.message}",
        raw_response: nil, http_status: nil }
    end
  end
end
