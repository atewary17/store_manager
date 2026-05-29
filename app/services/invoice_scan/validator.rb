module InvoiceScan
  # Deterministic validation of AI-parsed line items.
  # Runs math checks, field presence checks, and type checks.
  # Returns items annotated with a '_flags' array, plus a summary.
  class Validator
    TOLERANCE = 1.0  # Rs 1 tolerance for rounding differences

    def self.call(items)
      new(items).call
    end

    def initialize(items)
      @items = Array(items)
    end

    def call
      flagged = {}
      annotated = @items.map do |item|
        flags = []

        qty      = item['quantity'].to_f
        rate     = item['unit_rate'].to_f
        rpp      = item['rate_per_pack'].to_f
        value    = item['value'].to_f
        disc     = item['discount_amount'].to_f
        taxable  = item['taxable_amount'].to_f
        cgst_pct = item['cgst_percent'].to_f
        sgst_pct = item['sgst_percent'].to_f
        igst_pct = item['igst_percent'].to_f
        gst_rate = cgst_pct + sgst_pct + igst_pct
        cgst_amt = item['cgst_amount'].to_f
        sgst_amt = item['sgst_amount'].to_f
        igst_amt = item['igst_amount'].to_f
        gst_amt  = cgst_amt + sgst_amt + igst_amt
        total    = item['total_amount'].to_f

        # Use whichever rate satisfies qty × rate ≈ value
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
          if (exp - value).abs > TOLERANCE
            flags << "Value ₹#{value} ≠ Qty(#{qty.to_i}) × Rate(#{effective_rate}) = ₹#{exp}"
          end
        end

        # 2. Value − Discount = Taxable
        if value > 0 && taxable > 0
          exp = (value - disc).round(2)
          if (exp - taxable).abs > TOLERANCE
            flags << "Taxable ₹#{taxable} ≠ Value(#{value}) − Disc(#{disc}) = ₹#{exp}"
          end
        end

        # 3. Taxable × GST% = GST amount
        if taxable > 0 && gst_rate > 0 && gst_amt > 0
          exp = (taxable * gst_rate / 100.0).round(2)
          if (exp - gst_amt).abs > TOLERANCE
            flags << "GST ₹#{gst_amt} ≠ #{gst_rate.to_i}% × ₹#{taxable} = ₹#{exp}"
          end
        end

        # 4. Taxable + GST = Total
        if taxable > 0 && total > 0
          exp = (taxable + gst_amt).round(2)
          if (exp - total).abs > TOLERANCE
            flags << "Total ₹#{total} ≠ Taxable(₹#{taxable}) + GST(₹#{gst_amt}) = ₹#{exp}"
          end
        end

        # 5. Presence checks
        flags << 'material_code missing' if item['material_code'].blank?
        flags << 'description missing'   if item['description'].blank?
        flags << 'quantity is zero'      if qty == 0

        # 6. Type check — quantity should be an integer for unit-based items
        if qty > 0 && qty != qty.floor
          flags << "quantity #{qty} is not an integer"
        end

        sr = item['sr_no'].to_s
        flagged[sr] = flags if flags.any?

        item.merge('_flags' => flags)
      end

      {
        items:  annotated,
        flags:  flagged,
        valid:  flagged.empty?
      }
    end
  end
end
