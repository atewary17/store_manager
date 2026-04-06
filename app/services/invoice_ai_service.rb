# app/services/invoice_ai_service.rb
#
# Unified entry point for AI invoice extraction.
#
# SUPPORTED PROVIDERS:
#   groq        → Groq Llama 4 Scout (PRIMARY — free, ~14,400 req/day, WORKING ✅)
#   openrouter  → OpenRouter (FALLBACK — $1 free credit, many models)
#   mock        → Returns fake data (local dev, no API calls)
#
# REMOVED: gemini — quota errors on free tier, unreliable
#
# SETUP (config/local_env.yml):
#   INVOICE_AI_PROVIDER: "groq"
#   GROQ_API_KEY: "gsk_your_key_here"
#   OPENROUTER_API_KEY: "sk-or-your_key_here"   # optional fallback
#
# Get Groq key free:       https://console.groq.com
# Get OpenRouter key free: https://openrouter.ai  ($1 free credit on signup)
#
require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'openssl'

class InvoiceAiService

  def self.call(base64_data:, mime_type:, user_pref: nil)
    # Priority: user preference → env var → groq (default)
    provider = (user_pref.presence || ENV['INVOICE_AI_PROVIDER'] || 'groq').downcase

    result = case provider
             when 'groq'       then GroqInvoiceParser.new(base64_data:, mime_type:).call
             when 'openrouter' then OpenRouterInvoiceParser.new(base64_data:, mime_type:).call
             when 'mock'       then mock_response
             else
               Rails.logger.warn "[InvoiceAiService] Unknown provider '#{provider}', falling back to groq"
               GroqInvoiceParser.new(base64_data:, mime_type:).call
             end

    result.merge(provider: provider)
  end

  def self.mock_response
    Rails.logger.info '[InvoiceAiService] MOCK MODE'
    {
      success:      true,
      raw_response: '(mock)',
      error:        nil,
      provider:     'mock',
      data: {
        'supplier' => {
          'name'    => 'Mock Supplier Pvt Ltd',
          'gstin'   => '29AABCU9603R1ZX',
          'address' => '123 Test Street, Bengaluru'
        },
        'header' => {
          'invoice_number'        => 'MOCK-001',
          'invoice_date'          => Date.today.iso8601,
          'total_taxable_amount'  => 10000.0,
          'total_cgst'            => 900.0,
          'total_sgst'            => 900.0,
          'total_igst'            => 0.0,
          'total_amount'          => 11800.0,
          'cash_discount_amount'  => 0.0,
          'cash_discount_percent' => 0.0
        },
        'items' => [
          {
            'sr_no'          => 1,
            'material_code'  => 'MOCK-SKU-01',
            'description'    => 'Mock Interior Emulsion 4L White',
            'hsn_code'       => '3208',
            'pack_size'      => '4 LT',
            'num_packs'      => 10,
            'quantity'       => 40.0,
            'unit'           => 'LT',
            'unit_rate'      => 200.0,
            'taxable_amount' => 8000.0,
            'cgst_percent'   => 9.0,
            'cgst_amount'    => 720.0,
            'sgst_percent'   => 9.0,
            'sgst_amount'    => 720.0,
            'total_amount'   => 9440.0
          },
          {
            'sr_no'          => 2,
            'material_code'  => 'MOCK-SKU-02',
            'description'    => 'Mock Primer 1L',
            'hsn_code'       => '3208',
            'pack_size'      => '1 LT',
            'num_packs'      => 5,
            'quantity'       => 5.0,
            'unit'           => 'LT',
            'unit_rate'      => 400.0,
            'taxable_amount' => 2000.0,
            'cgst_percent'   => 9.0,
            'cgst_amount'    => 180.0,
            'sgst_percent'   => 9.0,
            'sgst_amount'    => 180.0,
            'total_amount'   => 2360.0
          }
        ]
      }
    }
  end
end