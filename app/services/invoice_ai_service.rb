# app/services/invoice_ai_service.rb
#
# Unified entry point for AI invoice extraction.
#
# SUPPORTED PROVIDERS:
#   groq        → Groq Llama 4 Scout (PRIMARY — free, ~14,400 req/day, WORKING ✅)
#   openrouter  → OpenRouter (FALLBACK — $1 free credit, many models)
#   mock        → Returns fake data (local dev, no API calls)
#
# ADDING A NEW PROVIDER:
#   1. Create app/services/<name>_invoice_parser.rb implementing:
#        MyParser.call(base64_data:, mime_type:) → { success:, data:, error:,
#                                                     raw_response:, provider:,
#                                                     preview_image: }
#      The data hash must include a '_meta' key:
#        '_meta' => { 'pages_scanned' => n, 'page_count' => n, 'pages_data' => [...] }
#   2. Register it in the PROVIDERS map below.
#   3. Set INVOICE_AI_PROVIDER=<name> in env or user preferences.
#
# SETUP (config/local_env.yml):
#   INVOICE_AI_PROVIDER: "groq"
#   GROQ_API_KEY: "gsk_your_key_here"
#   OPENROUTER_API_KEY: "sk-or-your_key_here"   # optional fallback
#
require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'openssl'

class InvoiceAiService

  # ── Provider registry — add new parsers here ──────────────────────────────
  PROVIDERS = {
    'groq'       => -> (b64, mime) { GroqInvoiceParser.call(base64_data: b64, mime_type: mime) },
    'openrouter' => -> (b64, mime) { OpenRouterInvoiceParser.call(base64_data: b64, mime_type: mime) },
    'mock'       => -> (_b64, _mime) { mock_response }
  }.freeze

  # ── Primary call ───────────────────────────────────────────────────────────
  #
  # Returns the provider result hash, always including:
  #   :success        Boolean
  #   :data           Hash  (nil on failure)
  #   :error          String (nil on success)
  #   :raw_response   String
  #   :provider       String
  #   :preview_image  String|nil  (base64 JPEG, set by parsers that generate it)
  #
  def self.call(base64_data:, mime_type:, user_pref: nil)
    provider_key = resolve_provider(user_pref)
    handler      = PROVIDERS[provider_key] || PROVIDERS['groq']

    result = handler.call(base64_data, mime_type)
    result.merge(provider: provider_key)
  end

  # ── Page-level abstraction (for providers that process one page at a time) ─
  #
  # Future providers that want per-page control can override this.
  # Currently Groq handles multi-page internally in GroqInvoiceParser.
  #
  def self.parse_page(base64_image:, mime_type:, page_num: 1, provider: nil)
    provider_key = resolve_provider(provider)
    handler      = PROVIDERS[provider_key] || PROVIDERS['groq']

    result = handler.call(base64_image, mime_type)
    result.merge(provider: provider_key, page_num: page_num)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def self.resolve_provider(user_pref)
    key = (user_pref.presence || ENV['INVOICE_AI_PROVIDER'] || 'groq').downcase.strip
    unless PROVIDERS.key?(key)
      Rails.logger.warn "[InvoiceAiService] Unknown provider '#{key}', falling back to groq"
      key = 'groq'
    end
    key
  end
  private_class_method :resolve_provider

  def self.mock_response
    Rails.logger.info '[InvoiceAiService] MOCK MODE'
    {
      success:       true,
      raw_response:  '(mock)',
      error:         nil,
      provider:      'mock',
      preview_image: nil,
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
          'cash_discount_percent' => 0.0,
          'page_number'           => 1,
          'total_pages'           => 1
        },
        '_meta' => {
          'pages_scanned' => 1,
          'page_count'    => 1,
          'pages_data'    => [{ 'page_num' => 1, 'item_count' => 2, 'page_number' => 1, 'total_pages' => 1 }]
        },
        'items' => [
          {
            'sr_no'          => 1,
            'material_code'  => 'MOCK-SKU-01',
            'description'    => 'Mock Interior Emulsion 4L White',
            'hsn_code'       => '3208',
            'pack_size'      => '4 LT',
            'num_packs'      => 10,
            'quantity'       => 10,
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
  private_class_method :mock_response
end
