# app/services/invoice_ai_service.rb
#
# Unified entry point for AI invoice extraction.
# Chooses provider based on INVOICE_AI_PROVIDER env var:
#   gemini  → GeminiInvoiceParser  (production default, 50 req/day free)
#   groq    → GroqInvoiceParser    (dev/staging, ~14400 req/day free, images only)
#   mock    → returns fake data    (local dev, no API calls)
#
# .env examples:
#   INVOICE_AI_PROVIDER=groq   GROQ_API_KEY=gsk_xxx
#   INVOICE_AI_PROVIDER=gemini GEMINI_API_KEY=AIza_xxx
#   INVOICE_AI_PROVIDER=mock
#
require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'openssl'

class InvoiceAiService

  def self.call(base64_data:, mime_type:)
    provider = (ENV['INVOICE_AI_PROVIDER'] || 'gemini').downcase

    case provider
    when 'groq'  then GroqInvoiceParser.new(base64_data:, mime_type:).call
    when 'mock'  then mock_response
    else              GeminiInvoiceParser.new(base64_data:, mime_type:).call
    end
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