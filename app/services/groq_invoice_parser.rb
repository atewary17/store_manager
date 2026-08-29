# app/services/groq_invoice_parser.rb
#
# Compatibility shim.
#
# The scanning logic now lives in the pipeline stack:
#   InvoiceScan::Runner       — walks stages, handles pages
#   InvoiceScan::Document     — PDF -> per-page JPEGs
#   InvoiceScan::Merger       — combines pages, runs supplier validation
#   InvoiceScan::Engines::*   — the swappable bits
#   InvoiceScan::Pipelines::* — which engines, in what order
#
# This class is kept so existing callers (InvoiceAiService, the digitise
# controller) keep working unchanged. New code should go through
# InvoiceScan::Runner with a pipeline from InvoiceScan::Pipelines::Registry.
#
class GroqInvoiceParser
  # Retained for callers that referenced the constant directly.
  GROQ_MODEL = ENV.fetch('GROQ_VISION_MODEL', 'qwen/qwen3.6-27b').freeze

  def self.call(base64_data:, mime_type:, supplier_hint: nil)
    result = InvoiceScan::Runner.call(
      pipeline:    InvoiceScan::Pipelines::Registry.default,
      base64_data: base64_data,
      mime_type:   mime_type,
      context:     InvoiceScan::Context.build(supplier_hint: supplier_hint)
    )

    result.merge(provider: 'groq')
  end
end
