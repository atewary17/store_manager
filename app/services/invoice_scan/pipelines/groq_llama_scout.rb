module InvoiceScan
  module Pipelines
    # Retired. Groq decommissioned this model on 17 July 2026 — requests to it
    # return HTTP 404 model_not_found.
    #
    # Kept registered on purpose: digitise_imports rows scanned before the
    # cutover reference it, and those imports still need to render what read
    # them. available? is false so it can never be chosen for new work.
    class GroqLlamaScout < Base
      MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct'.freeze

      def slug;          'groq_llama_scout'; end
      def display_name;  'Groq — Llama 4 Scout'; end
      def badge;         'RETIRED'; end
      def display_order; 90; end

      def tagline
        'Retired by Groq on 17 July 2026. Shown only on invoices scanned before then.'
      end

      # Never offered in the picker...
      def available?
        false
      end

      # ...but still resolves, because historical imports point at it.
      def resolvable?
        true
      end

      def unavailable_reason
        'Decommissioned by Groq on 17 July 2026.'
      end

      def stages
        [
          { role:   :preprocess,
            engine: InvoiceScan::Engines::Preprocess::ImageMagick,
            config: {} },
          { role:   :extract,
            engine: InvoiceScan::Engines::Extract::GroqVision,
            config: { model: MODEL } }
        ]
      end
    end
  end
end
