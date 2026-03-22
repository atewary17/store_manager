# app/services/open_router_invoice_parser.rb
#
# OpenRouter fallback for invoice scanning.
# Uses the same prompt and response format as GroqInvoiceParser.
#
# FREE SETUP:
#   1. Sign up at https://openrouter.ai
#   2. You get $1 free credit (no card needed initially)
#   3. Copy your API key to config/local_env.yml:
#      OPENROUTER_API_KEY: "sk-or-v1-xxxx"
#      INVOICE_AI_PROVIDER: "openrouter"
#
# Free models available on OpenRouter (no credit needed):
#   meta-llama/llama-3.2-11b-vision-instruct:free  ← vision, good for invoices
#   meta-llama/llama-3.1-8b-instruct:free           ← text only
#   google/gemma-3-12b-it:free                       ← text only
#
# With $1 credit (very cheap per request):
#   meta-llama/llama-4-scout                         ← best quality
#   google/gemini-2.0-flash-exp                      ← Gemini via OpenRouter (bypasses quota)
#
class OpenRouterInvoiceParser

  API_URL    = 'https://openrouter.ai/api/v1/chat/completions'.freeze
  # Best free vision model — handles invoices well
  FREE_MODEL = 'meta-llama/llama-3.2-11b-vision-instruct:free'.freeze
  PAID_MODEL = 'meta-llama/llama-4-scout'.freeze

  def initialize(base64_data:, mime_type:)
    @base64_data = base64_data
    @mime_type   = mime_type
  end

  def call
    api_key = ENV['OPENROUTER_API_KEY']
    return error_result('OPENROUTER_API_KEY not set. Get a free key at https://openrouter.ai') if api_key.blank?

    # Use paid model if key has credit, otherwise free model
    model = ENV['OPENROUTER_USE_FREE_MODEL'] == 'true' ? FREE_MODEL : PAID_MODEL

    body = {
      model:       model,
      max_tokens:  4096,
      temperature: 0.1,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image_url',
              image_url: {
                url: "data:#{@mime_type};base64,#{@base64_data}"
              }
            },
            {
              type: 'text',
              text: prompt
            }
          ]
        }
      ]
    }

    uri  = URI.parse(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 60
    http.open_timeout = 15

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type']  = 'application/json'
    req['Authorization'] = "Bearer #{api_key}"
    req['HTTP-Referer']  = 'https://mystoremanager.app'
    req['X-Title']       = 'MyStoreManager ERP'
    req.body = body.to_json

    res = http.request(req)

    unless res.code.to_i.between?(200, 299)
      # Handle free model rate limit — suggest switching
      if res.code.to_i == 429
        return error_result("OpenRouter rate limit hit. Try setting OPENROUTER_USE_FREE_MODEL=true or add credit at openrouter.ai")
      end
      return error_result("OpenRouter API returned #{res.code}: #{res.body[0..300]}")
    end

    parsed    = JSON.parse(res.body)
    raw_text  = parsed.dig('choices', 0, 'message', 'content').to_s.strip
    json_text = raw_text.gsub(/\A```json?\s*/i, '').gsub(/\s*```\z/, '').strip

    data = JSON.parse(json_text)

    {
      success:      true,
      data:         data,
      raw_response: raw_text,
      error:        nil
    }

  rescue JSON::ParserError => e
    error_result("Could not parse OpenRouter response as JSON: #{e.message}")
  rescue Net::ReadTimeout, Net::OpenTimeout
    error_result('OpenRouter request timed out (>60s)')
  rescue => e
    error_result("OpenRouter error: #{e.message}")
  end

  private

  def prompt
    # Reuse exact same prompt as Groq parser for consistent output
    GroqInvoiceParser::PROMPT
  end

  def error_result(msg)
    { success: false, data: nil, raw_response: nil, error: msg }
  end
end
