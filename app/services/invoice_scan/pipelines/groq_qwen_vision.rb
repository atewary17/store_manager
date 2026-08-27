module InvoiceScan
  module Pipelines
    # Default. Single-pass vision extraction with a full output budget.
    #
    # The 8,192-token output allowance is what lets long invoices and multi-page
    # PDFs return complete JSON. Groq counts that allowance against the
    # per-minute token limit whether or not it is used, so this pipeline needs a
    # paid plan — on the free tier every request is rejected with HTTP 413
    # before inference starts. See GroqQwenVisionLite for the constrained
    # variant.
    class GroqQwenVision < Base
      DEFAULT_MODEL = 'qwen/qwen3.6-27b'.freeze
      MAX_TOKENS    = 8192

      def slug;          'groq_qwen_vision'; end
      def display_name;  'Standard — Groq Qwen 3.6 Vision'; end
      def badge;         'RECOMMENDED'; end
      def display_order; 1; end

      def tagline
        'Handles invoices of any length, including multi-page PDFs. ' \
        'Requires a paid Groq plan.'
      end

      # Groq list pricing for qwen/qwen3.6-27b. Images are billed at $0 and
      # counted inside prompt_tokens.
      def input_price_per_mtok;  0.60; end
      def output_price_per_mtok; 3.00; end

      def stages
        [
          { role:   :preprocess,
            engine: InvoiceScan::Engines::Preprocess::ImageMagick,
            config: {} },
          { role:   :extract,
            engine: InvoiceScan::Engines::Extract::GroqVision,
            config: { model:      ENV.fetch('GROQ_VISION_MODEL', DEFAULT_MODEL),
                      max_tokens: MAX_TOKENS } }
        ]
      end
    end
  end
end
