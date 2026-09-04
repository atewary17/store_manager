module InvoiceScan
  module Pipelines
    # A pipeline is an ordered list of stages plus the metadata the admin
    # picker needs to render itself. Modelled on Suppliers::Base::Profile.
    #
    # Each stage is:
    #   { role: Symbol, engine: Class, config: Hash }
    #
    class Base
      def slug
        raise NotImplementedError, "#{self.class}#slug"
      end

      def display_name
        raise NotImplementedError, "#{self.class}#display_name"
      end

      def stages
        raise NotImplementedError, "#{self.class}#stages"
      end

      def tagline;       '';  end
      def badge;         nil; end   # 'RECOMMENDED' | 'FREE' | 'RETIRED'
      def display_order; 99;  end

      # Maximum pages this pipeline can handle in one scan, or nil for no
      # limit. Enforced by the Runner *before* any API call, so a document the
      # pipeline cannot process fails with an explanation rather than a raw
      # provider error partway through.
      def max_pages; nil; end

      # Per-million-token prices, used to show an estimated cost next to a
      # scan. nil means "unknown" — the UI shows tokens only.
      def input_price_per_mtok;  nil; end
      def output_price_per_mtok; nil; end

      # Estimated cost of one scan, in the pricing currency (USD).
      # Returns nil when this pipeline has no published pricing.
      def estimated_cost(prompt_tokens:, completion_tokens:)
        return nil if input_price_per_mtok.nil? || output_price_per_mtok.nil?

        ((prompt_tokens.to_i     / 1_000_000.0) * input_price_per_mtok) +
          ((completion_tokens.to_i / 1_000_000.0) * output_price_per_mtok)
      end

      # ── Two flags, deliberately separate ──────────────────────────────────
      #
      # available?  — offer this in the admin picker.
      # resolvable? — still resolve this slug when something references it.
      #
      # They differ because digitise_imports rows point at the pipeline that
      # scanned them. A retired pipeline must keep resolving so a year-old
      # import can still render "scanned with X", while never being selectable
      # for new work. An untested pipeline is the same shape: resolvable in
      # code, invisible in the UI, until it has been verified.
      def available?
        stages.all? { |s| s[:engine].available? }
      end

      def resolvable?
        true
      end

      # Reason shown next to a disabled option in the picker.
      def unavailable_reason
        missing = stages.reject { |s| s[:engine].available? }
        return nil if missing.empty?

        "Requires configuration for: #{missing.map { |s| s[:engine].name.demodulize }.join(', ')}"
      end
    end
  end
end
