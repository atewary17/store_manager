module InvoiceScan
  # Walks a pipeline's stages. Knows nothing about Groq, OCR, or any provider —
  # it only knows "run each stage in order, hand the output to the next".
  #
  # Page handling lives here rather than in an engine because "one call per
  # page" is a property of the pipeline shape, not of the model being called.
  #
  #   InvoiceScan::Runner.call(
  #     pipeline:    Pipelines::Registry.for('groq_qwen_vision'),
  #     base64_data: b64,
  #     mime_type:   'application/pdf',
  #     context:     Context.build(supplier_hint: 'Asian Paints')
  #   )
  #
  class Runner
    def self.call(pipeline:, base64_data:, mime_type:, context:)
      new(pipeline, base64_data, mime_type, context).call
    end

    def initialize(pipeline, base64_data, mime_type, context)
      @pipeline    = pipeline
      @base64_data = base64_data
      @mime_type   = mime_type
      @context     = context
    end

    def call
      document = Document.new(base64_data: @base64_data, mime_type: @mime_type)

      if (limit = @pipeline.max_pages) && document.pages.size > limit
        return too_many_pages(document, limit)
      end

      page_results = document.pages.each_with_index.map do |(b64, mime), idx|
        run_page(b64, mime, idx + 1)
      end

      Merger.call(page_results: page_results, context: @context)
            .merge(preview_image: document.preview_image, pipeline: @pipeline.slug)

    rescue => e
      { success: false, error: e.message, data: nil, raw_response: nil,
        preview_image: nil, pipeline: @pipeline.slug }
    end

    private

    # Fail before spending a single API call. Without this the first page
    # succeeds and page two returns a raw provider rate-limit error, which
    # tells the user nothing about what to do.
    def too_many_pages(document, limit)
      {
        success: false,
        data:    nil,
        error:   "This scanning process handles #{limit} #{'page'.pluralize(limit)} " \
                 "per invoice, but this file has #{document.pages.size}. " \
                 'Ask your administrator to switch to a process that supports ' \
                 'multi-page invoices.',
        raw_response:  nil,
        preview_image: document.preview_image,
        pipeline:      @pipeline.slug
      }
    end

    # Reduce the stages over one page. A stage that returns a failed EXTRACTION
    # short-circuits the rest of the chain for that page — other pages continue,
    # and Merger decides whether enough pages succeeded overall.
    def run_page(base64_data, mime_type, page_num)
      seed = { base64_data: base64_data, mime_type: mime_type, page_num: page_num }

      @pipeline.stages.reduce(seed) do |input, stage|
        output = stage[:engine].new(stage[:config]).call(input, @context)
        break output if failed?(output)
        output
      end
    end

    def failed?(output)
      output.is_a?(Hash) && output.key?(:success) && !output[:success]
    end
  end
end
