module Suppliers
  module Generic
    # Validation for Others/generic invoices.
    # Per line: qty × rate × (1 − disc_pct/100) ≈ amount
    # GST is summary-level only — no per-line GST check.
    class Validator < Suppliers::Base::Validator
      def self.call(items)
        new(items).call
      end

      def initialize(items)
        @items = Array(items)
      end

      def call
        flagged  = {}
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
        flags    = []
        qty      = item['quantity'].to_f
        rate     = item['unit_rate'].to_f
        disc_pct = item['discount_percent'].to_f
        amount   = item['total_amount'].to_f

        if qty > 0 && rate > 0 && amount > 0
          gross        = qty * rate
          exp_amount   = disc_pct > 0 ? (gross * (1 - disc_pct / 100.0)).round(2) : gross.round(2)
          flags << "Amount ₹#{amount} ≠ Qty(#{qty})×Rate(#{rate})×(1−#{disc_pct}%)=₹#{exp_amount}" \
            if (exp_amount - amount).abs > TOLERANCE
        end

        flags << 'description missing' if item['description'].blank?
        flags << 'quantity is zero'    if qty == 0

        flags
      end
    end
  end
end
