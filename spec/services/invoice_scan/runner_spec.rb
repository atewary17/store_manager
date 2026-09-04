require 'service_helper'

# Proves the Runner and the role contracts genuinely support a two-stage
# pipeline (:ocr -> :structure) before one exists in production.
#
# Both real presets today are single-stage, so without this the multi-stage
# path would first be exercised when Google Vision lands — exactly when a wrong
# contract is expensive. These stubs are test-only and never registered.
RSpec.describe InvoiceScan::Runner do
  # ── Test-only engines ──────────────────────────────────────────────────────

  class StubOcr < InvoiceScan::Engines::Base
    def self.role; :ocr; end

    def call(page, _context)
      {
        blocks: [
          { text: 'Interior Emulsion 4L',
            bbox: { x: 40, y: 220, w: 180, h: 14 }, confidence: 0.98 },
          { text: '10',
            bbox: { x: 320, y: 220, w: 24, h: 14 }, confidence: 0.99 }
        ],
        page:     { w: 1240, h: 1754 },
        page_num: page[:page_num]
      }
    end
  end

  class StubStructurer < InvoiceScan::Engines::Base
    def self.role; :structure; end

    def call(blocks, context)
      # The whole point of the contract: geometry survives the handoff, so a
      # structuring engine can rebuild columns from x-positions.
      raise 'contract violated: no bbox' unless blocks[:blocks].first.key?(:bbox)

      {
        success:      true,
        page_num:     blocks[:page_num],
        raw_response: '(stub)',
        error:        nil,
        data: {
          'header' => { 'invoice_number' => 'STUB-1', 'total_amount' => 2360.0 },
          'items'  => [{ 'description' => blocks[:blocks].first[:text],
                         'quantity' => 10, 'value' => 2000.0, 'unit_rate' => 200.0 }]
        }
      }
    end
  end

  class StubTwoStagePipeline < InvoiceScan::Pipelines::Base
    def slug;         'stub_two_stage'; end
    def display_name; 'Stub OCR + Structure'; end

    def stages
      [
        { role: :ocr,       engine: StubOcr,        config: {} },
        { role: :structure, engine: StubStructurer, config: {} }
      ]
    end
  end

  # ── Tests ──────────────────────────────────────────────────────────────────

  let(:context) { InvoiceScan::Context.build(supplier_hint: nil) }
  let(:page_b64) { Base64.strict_encode64('not-a-real-image') }

  def run(pipeline)
    described_class.call(
      pipeline:    pipeline,
      base64_data: page_b64,
      mime_type:   'image/jpeg',
      context:     context
    )
  end

  it 'runs a two-stage pipeline and merges the result' do
    result = run(StubTwoStagePipeline.new)

    expect(result[:success]).to be true
    expect(result[:pipeline]).to eq 'stub_two_stage'
    expect(result[:data]['items'].first['description']).to eq 'Interior Emulsion 4L'
    expect(result[:data]['header']['invoice_number']).to eq 'STUB-1'
  end

  it 'passes each stage output into the next' do
    expect_any_instance_of(StubStructurer)
      .to receive(:call)
      .with(hash_including(:blocks, :page), context)
      .and_call_original

    run(StubTwoStagePipeline.new)
  end

  it 'records pages scanned in _meta' do
    result = run(StubTwoStagePipeline.new)
    expect(result[:data]['_meta']['pages_scanned']).to eq 1
  end

  context 'when the document has more pages than the pipeline allows' do
    class SinglePagePipeline < InvoiceScan::Pipelines::Base
      def slug;         'stub_single_page'; end
      def display_name; 'Stub Single Page'; end
      def max_pages;    1; end
      def stages
        [{ role: :ocr,       engine: StubOcr,        config: {} },
         { role: :structure, engine: StubStructurer, config: {} }]
      end
    end

    let(:two_pages) { [['a', 'image/jpeg'], ['b', 'image/jpeg']] }

    before do
      allow_any_instance_of(InvoiceScan::Document).to receive(:pages).and_return(two_pages)
      allow_any_instance_of(InvoiceScan::Document).to receive(:preview_image).and_return(nil)
    end

    it 'fails before calling any engine' do
      expect_any_instance_of(StubOcr).not_to receive(:call)

      run(SinglePagePipeline.new)
    end

    it 'explains the limit and what to do about it' do
      result = run(SinglePagePipeline.new)

      expect(result[:success]).to be false
      expect(result[:error]).to include '1 page per invoice'
      expect(result[:error]).to include 'this file has 2'
      expect(result[:error]).to include 'administrator'
    end

    it 'allows a document within the limit' do
      allow_any_instance_of(InvoiceScan::Document)
        .to receive(:pages).and_return([['a', 'image/jpeg']])

      expect(run(SinglePagePipeline.new)[:success]).to be true
    end
  end

  context 'when a stage fails' do
    class FailingStage < InvoiceScan::Engines::Base
      def self.role; :structure; end
      def call(_input, _context)
        { success: false, error: 'boom', data: nil, raw_response: nil, page_num: 1 }
      end
    end

    class FailingPipeline < InvoiceScan::Pipelines::Base
      def slug;         'stub_failing'; end
      def display_name; 'Stub Failing'; end
      def stages
        [{ role: :ocr,       engine: StubOcr,     config: {} },
         { role: :structure, engine: FailingStage, config: {} }]
      end
    end

    it 'surfaces the failure rather than raising' do
      result = run(FailingPipeline.new)

      expect(result[:success]).to be false
      expect(result[:error]).to include 'boom'
    end
  end
end
