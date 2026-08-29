module InvoiceScan
  module Engines
    module Extract
      # PAGE -> EXTRACTION
      #
      # Single-pass vision extraction via Groq's OpenAI-compatible endpoint.
      #
      # The model is supplied by the pipeline as config rather than hardcoded —
      # that is what lets one engine class serve several presets, and what makes
      # the next model deprecation a preset change instead of a code change.
      #
      #   config[:model]       required — e.g. 'qwen/qwen3.6-27b'
      #   config[:max_tokens]  optional — defaults to 8192
      #
      class GroqVision < InvoiceScan::Engines::Base
        API_URL = 'https://api.groq.com/openai/v1/chat/completions'.freeze

        def self.role
          :extract
        end

        def self.available?
          ENV['GROQ_API_KEY'].present?
        end

        def call(page, context)
          raise 'GROQ_API_KEY not set' if api_key.blank?

          response = post(build_body(page, context.prompt))
          parse(response).merge(page_num: page[:page_num])
        rescue => e
          { success: false, error: "Page #{page[:page_num]}: #{e.message}",
            data: nil, raw_response: nil, page_num: page[:page_num] }
        end

        private

        def api_key
          ENV['GROQ_API_KEY']
        end

        def model
          config.fetch(:model) { raise ArgumentError, 'GroqVision requires config[:model]' }
        end

        def build_body(page, prompt)
          {
            model:       model,
            temperature: 0.1,
            max_tokens:  config.fetch(:max_tokens, 8192),
            # Qwen 3.x are reasoning models and prepend <think>...</think> to
            # their output by default, which is not valid JSON. Asking for
            # json_object suppresses the preamble and constrains the response.
            # Llama 4 Scout never needed this; the retired preset tolerates it.
            response_format: { type: 'json_object' },
            # Reading fields off an invoice needs no chain of thought, and the
            # reasoning tokens are billed and counted against the rate limit.
            # Groq accepts only 'none' or 'default' here.
            reasoning_effort: config.fetch(:reasoning_effort, 'none'),
            messages: [
              {
                role:    'user',
                content: [
                  { type: 'text', text: prompt },
                  { type: 'image_url',
                    image_url: { url: "data:#{page[:mime_type]};base64,#{page[:base64_data]}" } }
                ]
              }
            ]
          }
        end

        def post(body)
          uri  = URI.parse(API_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.read_timeout = 120
          http.open_timeout = 10
          # NOTE: carried over verbatim from GroqInvoiceParser to keep this
          # refactor behaviour-neutral. This disables certificate verification
          # entirely, not just the CRL check — see the security note in the
          # phase 3 summary. Worth fixing separately.
          http.verify_mode  = OpenSSL::SSL::VERIFY_NONE

          req = Net::HTTP::Post.new(uri.request_uri)
          req['Content-Type']  = 'application/json'
          req['Authorization'] = "Bearer #{api_key}"
          req.body = body.to_json

          http.request(req)
        end

        def parse(response)
          unless response.code.to_i == 200
            return { success: false, data: nil, raw_response: response.body,
                     error: "Groq HTTP #{response.code}: #{response.body.to_s.truncate(300)}" }
          end

          outer = JSON.parse(response.body)
          text  = outer.dig('choices', 0, 'message', 'content').to_s.strip
          # Belt and braces: strip a reasoning preamble if one slips through,
          # then any markdown fence around the JSON.
          text  = text.sub(/\A<think>.*?<\/think>\s*/m, '').strip
          text  = text.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip

          { success: true, data: JSON.parse(text), raw_response: text, error: nil,
            usage: usage_from(outer) }
        rescue JSON::ParserError => e
          # Tokens were still spent even though the response did not parse —
          # report them so usage totals stay honest.
          { success: false, data: nil, raw_response: text.to_s,
            error: "JSON parse failed: #{e.message}",
            usage: usage_from(outer) }
        end

        # Groq returns OpenAI-shaped usage on every successful response.
        def usage_from(payload)
          u = payload.is_a?(Hash) ? payload['usage'] : nil
          return { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 } if u.blank?

          {
            prompt_tokens:     u['prompt_tokens'].to_i,
            completion_tokens: u['completion_tokens'].to_i,
            total_tokens:      u['total_tokens'].to_i
          }
        end
      end
    end
  end
end
