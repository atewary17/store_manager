# app/services/invoice_ai_service.rb
#
# Unified entry point for AI invoice extraction.
#
# Which scanning process runs is chosen per organisation by a super admin on
# the organisation page, and stored in organisations.settings['ai_pipeline'].
#
# RESOLUTION ORDER (first match wins):
#   1. the organisation's configured pipeline   ← admin policy, normally wins
#   2. a super admin's personal override        ← testing only
#   3. INVOICE_SCAN_PIPELINE env                ← server default
#   4. Pipelines::Registry::DEFAULT
#
# A non-super-admin's preferences are deliberately ignored: the point of the
# org setting is that one admin decides for the whole organisation.
#
# ADDING A SCANNING PROCESS:
#   Create an InvoiceScan::Pipelines::* class and register it in
#   InvoiceScan::Pipelines::Registry. It then appears in the admin picker on
#   its own — no change to this file or to the organisation view.
#
# SETUP (config/local_env.yml):
#   GROQ_API_KEY: "gsk_your_key_here"
#
require 'net/http'
require 'uri'
require 'base64'
require 'json'
require 'openssl'

class InvoiceAiService

  MOCK = 'mock'.freeze

  # ── Primary call ───────────────────────────────────────────────────────────
  #
  # Returns the result hash, always including:
  #   :success        Boolean
  #   :data           Hash  (nil on failure)
  #   :error          String (nil on success)
  #   :raw_response   String
  #   :provider       String — the pipeline slug that actually ran
  #   :pipeline       String — same value; :provider kept for existing callers
  #   :preview_image  String|nil  (base64 JPEG, for PDFs)
  #
  def self.call(base64_data:, mime_type:, user_pref: nil, supplier_hint: nil,
                organisation: nil, user: nil)
    if mock?(user_pref)
      return mock_response.merge(provider: MOCK, pipeline: MOCK)
    end

    pipeline = resolve_pipeline(organisation: organisation, user: user, user_pref: user_pref)

    result = InvoiceScan::Runner.call(
      pipeline:    pipeline,
      base64_data: base64_data,
      mime_type:   mime_type,
      context:     InvoiceScan::Context.build(
        supplier_hint: supplier_hint,
        organisation:  organisation
      )
    )

    result.merge(provider: pipeline.slug)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def self.mock?(user_pref)
    user_pref.to_s.downcase.strip == MOCK ||
      ENV['INVOICE_AI_PROVIDER'].to_s.downcase.strip == MOCK
  end
  private_class_method :mock?

  # Organisation policy wins. A personal override is honoured only for super
  # admins, so an ordinary user cannot opt out of what their admin configured.
  def self.resolve_pipeline(organisation:, user: nil, user_pref: nil)
    if user&.super_admin? && user_pref.present?
      return InvoiceScan::Pipelines::Registry.for(user_pref)
    end

    return organisation.scan_pipeline if organisation.respond_to?(:scan_pipeline)

    InvoiceScan::Pipelines::Registry.for(ENV['INVOICE_SCAN_PIPELINE'])
  end
  private_class_method :resolve_pipeline

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
