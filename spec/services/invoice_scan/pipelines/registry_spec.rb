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
  end
end
