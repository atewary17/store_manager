require 'service_helper'

RSpec.describe 'Token usage capture' do
  let(:context) { InvoiceScan::Context.build(supplier_hint: nil) }

  # Returns fixed usage so aggregation can be asserted exactly.
  class UsageStubEngine < InvoiceScan::Engines::Base
    def self.role; :extract; end

    def call(page, _context)
      {
        success:      true,
        page_num:     page[:page_num],
        raw_response: '(stub)',
        error:        nil,
        usage: { prompt_tokens: 1_000, completion_tokens: 500, total_tokens: 1_500 },
        data: {
          'header' => { 'invoice_number' => 'T-1' },
          'items'  => [{ 'description' => 'Paint', 'quantity' => 1, 'value' => 100.0 }]
        }
      }
    end
  end

  class UsagePipeline < InvoiceScan::Pipelines::Base
    def slug;         'usage_stub'; end
    def display_name; 'Usage Stub'; end
    def stages
      [{ role: :extract, engine: UsageStubEngine, config: {} }]
    end
  end

  def run(pipeline)
    InvoiceScan::Runner.call(
      pipeline:    pipeline,
      base64_data: Base64.strict_encode64('img'),
      mime_type:   'image/jpeg',
      context:     context
    )
  end

  it 'returns provider-reported usage on the result' do
    result = run(UsagePipeline.new)

    expect(result[:usage]).to eq(
      prompt_tokens: 1_000, completion_tokens: 500, total_tokens: 1_500
    )
  end

  it 'records the headline total in _meta' do
    result = run(UsagePipeline.new)

    expect(result[:data]['_meta']['usage']['total_tokens']).to eq 1_500
  end

  it 'keeps a per-page breakdown in pages_data' do
    result = run(UsagePipeline.new)
    page   = result[:data]['_meta']['pages_data'].first

    expect(page['usage']['prompt_tokens']).to eq 1_000
    expect(page['usage']['completion_tokens']).to eq 500
  end

  describe 'Merger aggregation across pages' do
    it 'sums usage from every page, including failed ones' do
      results = [
        { success: true, page_num: 1, data: { 'items' => [] }, raw_response: 'a',
          usage: { prompt_tokens: 1_000, completion_tokens: 500, total_tokens: 1_500 } },
        # Reached the model, came back unparseable — still billed.
        { success: false, page_num: 2, data: nil, error: 'bad json', raw_response: 'b',
          usage: { prompt_tokens: 900, completion_tokens: 100, total_tokens: 1_000 } }
      ]

      merged = InvoiceScan::Merger.call(page_results: results, context: context)

      expect(merged[:usage][:total_tokens]).to eq 2_500
      expect(merged[:usage][:prompt_tokens]).to eq 1_900
    end

    it 'reports usage even when every page failed' do
      results = [
        { success: false, page_num: 1, data: nil, error: 'boom', raw_response: nil,
          usage: { prompt_tokens: 700, completion_tokens: 0, total_tokens: 700 } }
      ]

      merged = InvoiceScan::Merger.call(page_results: results, context: context)

      expect(merged[:success]).to be false
      expect(merged[:usage][:total_tokens]).to eq 700
    end

    it 'treats a missing usage key as zero rather than raising' do
      results = [{ success: true, page_num: 1, data: { 'items' => [] }, raw_response: 'a' }]

      merged = InvoiceScan::Merger.call(page_results: results, context: context)

      expect(merged[:usage][:total_tokens]).to eq 0
    end
  end
end
