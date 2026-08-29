require 'service_helper'

RSpec.describe InvoiceScan::Pipelines::Registry do
  describe '.available' do
    it 'excludes the retired Llama 4 Scout pipeline' do
      slugs = described_class.available.map(&:slug)
      expect(slugs).not_to include 'groq_llama_scout'
    end
  end

  describe '.for' do
    it 'still resolves the retired pipeline, so old imports render' do
      pipeline = described_class.for('groq_llama_scout')

      expect(pipeline.slug).to eq 'groq_llama_scout'
      expect(pipeline.available?).to be false
      expect(pipeline.resolvable?).to be true
    end

    it 'falls back to the default for an unknown slug' do
      expect(described_class.for('does_not_exist').slug)
        .to eq described_class::DEFAULT
    end

    it 'falls back to the default for a blank slug' do
      expect(described_class.for(nil).slug).to eq described_class::DEFAULT
    end
  end

  describe 'the default pipeline' do
    it 'is single-stage vision on the current Groq model' do
      stages = described_class.default.stages

      expect(stages.map { |s| s[:role] }).to eq %i[preprocess extract]
      expect(stages.last[:config][:model]).to eq 'qwen/qwen3.6-27b'
    end

    it 'keeps the full output budget — the default is not the workaround' do
      expect(described_class.default.stages.last[:config][:max_tokens]).to eq 8192
      expect(described_class.default.max_pages).to be_nil
    end
  end

  describe 'the free-tier variant' do
    subject(:lite) { described_class.for('groq_qwen_vision_lite') }

    it 'is offered alongside the standard pipeline' do
      expect(described_class.available.map(&:slug))
        .to include('groq_qwen_vision', 'groq_qwen_vision_lite')
    end

    it 'caps output so one page fits under the free-tier per-minute limit' do
      expect(lite.stages.last[:config][:max_tokens]).to eq 3000
    end

    it 'refuses multi-page documents, which cannot fit at any token setting' do
      expect(lite.max_pages).to eq 1
    end

    it 'uses the same engine and model as the standard pipeline' do
      standard = described_class.default

      expect(lite.stages.last[:engine]).to eq standard.stages.last[:engine]
      expect(lite.stages.last[:config][:model]).to eq standard.stages.last[:config][:model]
    end
  end

  describe 'cost estimation' do
    it 'prices a scan from the pipeline’s published rates' do
      cost = described_class.default.estimated_cost(
        prompt_tokens: 1_000_000, completion_tokens: 1_000_000
      )

      expect(cost).to be_within(0.001).of(3.60) # $0.60 in + $3.00 out
    end
  end
end
