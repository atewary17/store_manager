module Suppliers
  module ShalimarPaints
    # Validation for Shalimar Paints line items.
    # Shalimar invoices use rate-per-pack pricing; GST is applied at summary level only.
    # Per-line check: num_packs × rate_per_pack = amount
    class Validator < Suppliers::Base::Validator
      def self.call(items)
        new(items).call
      end

      def initialize(items)
        @items = Array(items)
      end

      def call
        flagged = {}
        annotated = @items.map do |item|
          flags = run_checks(item)
          sr    = item['sr_no'].to_s
          flagged[sr] = flags if flags.any?
          item.merge('_flags' => flags)
        end
        { items: annotated, flags: flagged, valid: flagged.empty? }
      end

      private

      def run_checks(item)
        flags     = []
        num_packs = item['num_packs'].to_f
        rpp       = item['rate_per_pack'].to_f
        amount    = item['total_amount'].to_f
        pack_size = item['pack_size'].to_s.strip

        # 1. num_packs × rate_per_pack = amount
        if num_packs > 0 && rpp > 0 && amount > 0
          exp = (num_packs * rpp).round(2)
          flags << "Amount ₹#{amount} ≠ Packs(#{num_packs})×Rate(#{rpp})=₹#{exp}" if (exp - amount).abs > TOLERANCE
        end

        # Presence
        flags << 'pack_size missing' if pack_size.blank?
        flags << 'num_packs is zero' if num_packs == 0
        flags << 'description missing' if item['description'].blank?

        flags
      end
    end
  end
end
