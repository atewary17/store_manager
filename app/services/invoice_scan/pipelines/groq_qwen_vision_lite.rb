module InvoiceScan
  module Pipelines
    # Same engine and model as GroqQwenVision, tuned to fit Groq's free tier.
    #
    # WHY THE LIMITS
    #
    # Groq counts the reserved max_tokens against the per-minute token budget,
    # not the tokens actually generated. On the free tier (8,000 TPM) a single
    # page costs roughly:
    #
    #     brand prompt   ~1,800
    #     invoice image  ~2,900
    #     max_tokens      8,192   ← reserved, never sent
    #                    ───────
    #                    ~12,900  → HTTP 413
    #
    # Capping the output allowance at 3,000 brings one page to ~7,700, just
    # under the limit. Two pages cannot fit at any setting, because TPM is a
    # rolling per-minute budget and each page is a separate request — hence
    # max_pages.
    #
    # The trade-off is real: a dense invoice needing more than 3,000 tokens of
    # JSON is truncated rather than rejected. This exists so scanning works
    # without a paid plan, not because it is the better configuration.
    class GroqQwenVisionLite < Base
      DEFAULT_MODEL = 'qwen/qwen3.6-27b'.freeze
      MAX_TOKENS    = 3000

      def slug;          'groq_qwen_vision_lite'; end
      def display_name;  'Reduced — Groq Qwen 3.6 Vision'; end
      def badge;         'FREE TIER'; end
      def display_order; 2; end

      def tagline
        'Works within Groq\'s free tier. Single-page invoices only, and very ' \
        'long invoices may be cut short.'
      end

      def max_pages; 1; end

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
