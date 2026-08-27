module InvoiceScan
  module Pipelines
    # The list of scanning pipelines the system knows about.
    #
    # To add one: create the pipeline class, add it here. Nothing else changes —
    # the admin picker renders from .available, and the Runner executes whatever
    # stages the pipeline declares.
    class Registry
      PRESETS = [
        InvoiceScan::Pipelines::GroqQwenVision,
        InvoiceScan::Pipelines::GroqQwenVisionLite,
        InvoiceScan::Pipelines::GroqLlamaScout
      ].freeze

      DEFAULT = 'groq_qwen_vision'.freeze

      # Every registered pipeline, selectable or not.
      def self.all
        PRESETS.map(&:new).sort_by(&:display_order)
      end

      # What an admin may choose right now.
      def self.available
        all.select(&:available?)
      end

      # What an admin sees greyed out — registered, currently unusable, but
      # worth showing so nobody wonders whether the option exists.
      def self.unavailable
        all.reject(&:available?).select { |p| p.badge != 'RETIRED' }
      end

      # Resolve a stored slug. Falls back to the default rather than raising,
      # so a stale organisation setting degrades to a working scan.
      def self.for(slug)
        found = all.find { |p| p.slug == slug.to_s }
        return found if found&.resolvable?

        if slug.present?
          Rails.logger.warn "[InvoiceScan::Pipelines] Unknown pipeline '#{slug}', using #{DEFAULT}"
        end
        default
      end

      def self.default
        all.find { |p| p.slug == DEFAULT }
      end
    end
  end
end
