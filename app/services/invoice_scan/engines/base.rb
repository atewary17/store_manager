module InvoiceScan
  module Engines
    # ── ROLE CONTRACTS ────────────────────────────────────────────────────────
    #
    # A "role contract" is an agreed shape of data a stage accepts and returns.
    # It is a promise, not a class. Honour the promise and any engine can be
    # dropped into that position without the calling code changing.
    #
    # Every engine receives (input, context) and returns the shape below.
    # `context` is an InvoiceScan::Context — supplier profile, prompt, org.
    #
    #   :preprocess   PAGE   -> PAGE
    #       Image cleanup. Never brand-aware.
    #
    #   :ocr          PAGE   -> BLOCKS
    #       Image to text. Never brand-aware.
    #       BLOCKS MUST CARRY GEOMETRY — see the warning below.
    #
    #   :extract      PAGE   -> EXTRACTION
    #       Single-pass vision model: image straight to structured data.
    #       Brand-aware — reads context.prompt.
    #
    #   :structure    BLOCKS -> EXTRACTION
    #       Text-to-JSON for two-stage pipelines.
    #       Brand-aware — reads context.prompt.
    #
    # ── SHAPES ────────────────────────────────────────────────────────────────
    #
    #   PAGE       { base64_data: String, mime_type: String, page_num: Integer }
    #
    #   BLOCKS     { blocks: [{ text: String,
    #                           bbox: { x:, y:, w:, h: },
    #                           confidence: Float }],
    #                page: { w: Integer, h: Integer },
    #                page_num: Integer }
    #
    #   EXTRACTION { success: Boolean, data: Hash|nil, error: String|nil,
    #                raw_response: String|nil, page_num: Integer }
    #
    # ── WHY :ocr MUST RETURN GEOMETRY ─────────────────────────────────────────
    #
    # Invoices encode meaning in column position — whether a number is quantity,
    # rate, or amount is decided by where it sits on the page, not by what
    # precedes it in reading order. An OCR stage that returns a flat string has
    # already destroyed that information before the structuring model sees it,
    # and no prompt can recover it. Any :ocr engine that cannot supply bounding
    # boxes is not usable for invoices.
    #
    class Base
      # Which role this engine fills. See the contracts above.
      def self.role
        raise NotImplementedError, "#{self}.role"
      end

      # Whether this engine can run at all — usually an API key check.
      # Pipelines use this to decide what to offer in the admin picker.
      def self.available?
        true
      end

      def initialize(config = {})
        @config = config || {}
      end

      def call(_input, _context)
        raise NotImplementedError, "#{self.class}#call"
      end

      private

      attr_reader :config
    end
  end
end
