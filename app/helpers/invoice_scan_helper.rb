module InvoiceScanHelper
  # Human name for the pipeline that scanned an import.
  #
  # digitise_imports.ai_provider stores a pipeline slug. Older rows hold a bare
  # provider name ('groq'), which Registry.for maps forward. Retired pipelines
  # still resolve, so an old import keeps showing what actually read it.
  def scan_pipeline_name(slug)
    return nil if slug.blank?

    InvoiceScan::Pipelines::Registry.for(slug).display_name
  end

  # "12,951 tok · 4,759 in / 8,192 out"
  # Returns nil when nothing was measured, so callers can skip the row.
  def scan_token_summary(import)
    return nil if import.total_tokens.to_i.zero?

    "#{number_with_delimiter(import.total_tokens)} tok · " \
      "#{number_with_delimiter(import.prompt_tokens)} in / " \
      "#{number_with_delimiter(import.completion_tokens)} out"
  end

  # Estimated provider cost for one scan, using the pipeline's published
  # per-million-token prices. nil when that pipeline has no pricing.
  #
  # Shown in USD because that is the currency the provider bills in —
  # converting to INR here would invent an exchange rate.
  def scan_cost_estimate(import)
    return nil if import.total_tokens.to_i.zero?

    pipeline = InvoiceScan::Pipelines::Registry.for(import.ai_provider)
    cost     = pipeline.estimated_cost(
      prompt_tokens:     import.prompt_tokens,
      completion_tokens: import.completion_tokens
    )
    return nil if cost.nil?

    # Sub-cent scans are the norm; 4dp keeps them from all reading as $0.00.
    format('$%.4f', cost)
  end

  # Per-page rows behind the headline, for the expandable breakdown.
  # => [{ page: 1, total: 7_712, prompt: 4_712, completion: 3_000 }, ...]
  def scan_token_breakdown(import)
    pages = import.parsed_data&.dig('_meta', 'pages_data')
    return [] if pages.blank?

    pages.filter_map do |page|
      usage = page['usage']
      next if usage.blank? || usage['total_tokens'].to_i.zero?

      {
        page:       page['page_num'],
        total:      usage['total_tokens'].to_i,
        prompt:     usage['prompt_tokens'].to_i,
        completion: usage['completion_tokens'].to_i
      }
    end
  end
end
