module InvoiceScan
  module Pipelines
    # Current default. Single-pass vision extraction on Groq.
    class GroqQwenVision < Base
      DEFAULT_MODEL = 'qwen/qwen3.6-27b'.freeze

      def slug;          'groq_qwen_vision'; end
      def display_name;  'Groq — Qwen 3.6 Vision'; end
      def badge;         'RECOMMENDED'; end
      def display_order; 1; end

      def tagline
        'Reads the invoice image directly in one pass. Fast, low cost, and the ' \
        'best fit for most suppliers.'
      end

      def stages
        [
          { role:   :preprocess,
            engine: InvoiceScan::Engines::Preprocess::ImageMagick,
            config: {} },
          { role:   :extract,
            engine: InvoiceScan::Engines::Extract::GroqVision,
            config: { model: ENV.fetch('GROQ_VISION_MODEL', DEFAULT_MODEL) } }
        ]
      end
    end
  end
end
