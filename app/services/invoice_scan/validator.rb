module InvoiceScan
  class Validator
    TOLERANCE   = 0.01  # 1% relative tolerance
    MIN_RUPEES  = 1.0   # minimum absolute tolerance ₹1

    def self.call(items)
      new.call(items)
    end

    def call(items)
      flags = {}

      items.each_with_index do |item, idx|
        line_flags = []
        sr  = item['sr_no'] || (idx + 1)

        qty  = item['quantity'].to_f
        rate = item['unit_rate'].to_f
        val  = item['value'].to_f
        tax  = item['taxable_amount'].to_f
        tot  = item['total_amount'].to_f
        cgst = item['cgst_amount'].to_f
        sgst = item['sgst_amount'].to_f
        igst = item['igst_amount'].to_f
        disc = item['discount_amount'].to_f

        # qty × unit_rate ≈ value
        if qty > 0 && rate > 0 && val > 0
          expected = qty * rate
          tol = [val * TOLERANCE, MIN_RUPEES].max
          if (expected - val).abs > tol
            line_flags << "qty×rate #{qty}×#{rate}=#{expected.round(2)} ≠ value #{val}"
          end
        end

        # value − discount ≈ taxable_amount
        if val > 0 && tax > 0
          expected = val - disc
          tol = [tax * TOLERANCE, MIN_RUPEES].max
          if (expected - tax).abs > tol
            line_flags << "value−disc #{val}−#{disc}=#{expected.round(2)} ≠ taxable #{tax}"
          end
        end

        # taxable + cgst + sgst + igst ≈ total_amount
        if tot > 0 && tax > 0
          expected = tax + cgst + sgst + igst
          tol = [tot * TOLERANCE, MIN_RUPEES].max
          if (expected - tot).abs > tol
            line_flags << "tax+gst #{expected.round(2)} ≠ total #{tot}"
          end
        end

        # presence checks
        line_flags << 'missing material_code' if item['material_code'].blank?
        line_flags << 'missing description'   if item['description'].blank?
        line_flags << 'missing unit_rate'      if item['unit_rate'].to_f.zero?

        # quantity must be an integer value
        if item['quantity'].present? && item['quantity'].to_f != item['quantity'].to_f.floor
          line_flags << "quantity not integer (#{item['quantity']})"
        end

        flags[sr] = line_flags if line_flags.any?
      end

      { items: items, flags: flags, valid: flags.empty? }
    end
  end
end
