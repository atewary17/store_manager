module Suppliers
  module AsianPaints
    # Deterministic math validation for Asian Paints line items.
    # Checks: qty×rate=value, value−disc=taxable, taxable×gst%=gst_amt, taxable+gst=total
    # Also: material_code presence, description presence, integer quantity.
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
        flags    = []
        qty      = item['quantity'].to_f
        rate     = item['unit_rate'].to_f
        rpp      = item['rate_per_pack'].to_f
        value    = item['value'].to_f
        disc     = item['discount_amount'].to_f
        taxable  = item['taxable_amount'].to_f
        gst_rate = item['cgst_percent'].to_f + item['sgst_percent'].to_f + item['igst_percent'].to_f
        gst_amt  = item['cgst_amount'].to_f  + item['sgst_amount'].to_f  + item['igst_amount'].to_f
        total    = item['total_amount'].to_f

        # Prefer whichever rate satisfies qty × rate ≈ value
        effective_rate = if rate > 0 && qty > 0 && value > 0 && (qty * rate - value).abs <= TOLERANCE
          rate
        elsif rpp > 0 && qty > 0 && value > 0 && (qty * rpp - value).abs <= TOLERANCE
          item['unit_rate'] = rpp
          rpp
        else
          rate > 0 ? rate : rpp
        end

        # 1. Qty × Rate = Value
        if qty > 0 && effective_rate > 0 && value > 0
          exp = (qty * effective_rate).round(2)
          flags << "Value ₹#{value} ≠ Qty(#{qty.to_i})×Rate(#{effective_rate})=₹#{exp}" if (exp - value).abs > TOLERANCE
        end

        # 2. Value − Discount = Taxable
        if value > 0 && taxable > 0
          exp = (value - disc).round(2)
          flags << "Taxable ₹#{taxable} ≠ Value(#{value})−Disc(#{disc})=₹#{exp}" if (exp - taxable).abs > TOLERANCE
        end

        # 3. Taxable × GST% = GST amount
        if taxable > 0 && gst_rate > 0 && gst_amt > 0
          exp = (taxable * gst_rate / 100.0).round(2)
          flags << "GST ₹#{gst_amt} ≠ #{gst_rate.to_i}%×₹#{taxable}=₹#{exp}" if (exp - gst_amt).abs > TOLERANCE
        end

        # 4. Taxable + GST = Total
        if taxable > 0 && total > 0
          exp = (taxable + gst_amt).round(2)
          flags << "Total ₹#{total} ≠ Taxable(₹#{taxable})+GST(₹#{gst_amt})=₹#{exp}" if (exp - total).abs > TOLERANCE
        end

        # Presence
        flags << 'material_code missing' if item['material_code'].blank?
        flags << 'description missing'   if item['description'].blank?
        flags << 'quantity is zero'      if qty == 0

        # Type
        flags << "quantity #{qty} is not an integer" if qty > 0 && qty != qty.floor

        flags
      end
    end
  end
end
