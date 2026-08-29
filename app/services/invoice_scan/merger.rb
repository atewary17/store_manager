module InvoiceScan
  # Combines per-page EXTRACTION results into one invoice, then validates.
  #
  # Lifted verbatim from GroqInvoiceParser#merge_page_results. None of this was
  # ever Groq-specific — it was just trapped inside one provider, which is why
  # GeminiInvoiceParser has no multi-page handling at all. Living here, every
  # engine gets it for free.
  class Merger
    def self.call(page_results:, context:)
      new(page_results, context).call
    end

    def initialize(page_results, context)
      @page_results = page_results
      @context      = context
    end

    def call
      successful = @page_results.select { |r| r[:success] && r[:data].present? }

      # Totalled across every page, including failed ones — a page that reached
      # the model and came back unparseable still cost tokens.
      usage = total_usage

      if successful.empty?
        return {
          success:      false,
          error:        @page_results.map { |r| r[:error] }.compact.join(' | '),
          data:         nil,
          raw_response: @page_results.first&.dig(:raw_response),
          usage:        usage
        }
      end

      base      = successful.first[:data]
      all_items = successful.flat_map { |r| r[:data]['items'] || [] }

      # Merge header totals across ALL pages. On multi-page invoices the line
      # items are on page 1 but the GST/total summary is often on the LAST page.
      # Without this, page-1's zero totals would mask the real figures.
      base['header'] = merge_headers(successful.map { |r| r[:data]['header'] }.compact)

      resolve_unit_rates(all_items)

      validation = @context.supplier_profile.validator.call(all_items)

      ai_total_pages = successful.map { |r| r[:data].dig('header', 'total_pages').to_i }.max
      pages_scanned  = successful.size

      merged_data = base.merge(
        'items' => validation[:items],
        '_meta' => {
          'pages_scanned'    => pages_scanned,
          'page_count'       => [ai_total_pages, pages_scanned].max,
          'supplier_hint'    => @context.supplier_hint,
          'validation_flags' => validation[:flags],
          'validation_valid' => validation[:valid],
          'usage'            => usage.stringify_keys,
          'pages_data'       => successful.map { |r|
            {
              'page_num'    => r[:page_num],
              'item_count'  => (r[:data]['items'] || []).size,
              'page_number' => r[:data].dig('header', 'page_number'),
              'total_pages' => r[:data].dig('header', 'total_pages'),
              # Per-page breakdown behind the headline total.
              'usage'       => (r[:usage] || {}).stringify_keys
            }
          }
        }
      )

      {
        success:      true,
        data:         merged_data,
        raw_response: successful.map { |r| r[:raw_response] }.join("\n---page---\n"),
        error:        nil,
        usage:        usage
      }
    end

    private

    def total_usage
      @page_results.each_with_object(
        { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      ) do |result, sum|
        u = result[:usage] || {}
        sum[:prompt_tokens]     += u[:prompt_tokens].to_i
        sum[:completion_tokens] += u[:completion_tokens].to_i
        sum[:total_tokens]      += u[:total_tokens].to_i
      end
    end

    # Resolve unit_rate from rate_per_pack where the arithmetic agrees.
    def resolve_unit_rates(items)
      items.each do |item|
        qty = item['quantity'].to_f
        val = item['value'].to_f
        rpp = item['rate_per_pack'].to_f
        ur  = item['unit_rate'].to_f
        next unless qty > 0 && val > 0

        tol = [val * 0.005, 1.0].max
        if rpp > 0 && (qty * rpp - val).abs <= tol
          item['unit_rate'] = rpp
        elsif !(ur > 0 && (qty * ur - val).abs <= tol) && rpp > 0
          item['unit_rate'] = rpp
        end
      end
    end

    # Combine headers from every page into one. Starts from page 1's header
    # (which carries supplier/invoice identity) and fills numeric total fields
    # with the largest non-zero value seen on any page — so summary figures on a
    # later page are not lost. Text fields take the first non-blank value.
    def merge_headers(headers)
      return {} if headers.empty?
      merged = headers.first.dup

      numeric_totals = %w[
        total_cgst total_sgst total_igst total_amount total_taxable_amount
        cash_discount_amount cash_discount_percent
      ]
      numeric_totals.each do |field|
        best = headers.map { |h| h[field].to_f }.max
        merged[field] = best if best.to_f > merged[field].to_f
      end

      text_fields = %w[amount_in_words invoice_number invoice_date delivery_number
                       place_of_supply po_reference]
      text_fields.each do |field|
        next if merged[field].present?
        found = headers.map { |h| h[field] }.find(&:present?)
        merged[field] = found if found
      end

      merged
    end
  end
end
