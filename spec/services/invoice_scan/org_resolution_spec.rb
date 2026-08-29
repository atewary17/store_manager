require 'service_helper'

# Organisation#scan_pipeline_slug is the single place the scanning process is
# decided. These specs pin the precedence order and the legacy migration path,
# because getting either wrong silently changes what reads every invoice.
RSpec.describe 'Organisation scan pipeline resolution' do
  # Avoids touching the database — this logic is pure settings reading.
  def org(settings)
    Organisation.new(name: 'Test Org', settings: settings)
  end

  around do |example|
    original = ENV['INVOICE_SCAN_PIPELINE']
    example.run
    ENV['INVOICE_SCAN_PIPELINE'] = original
  end

  it 'uses the configured pipeline when one is set' do
    expect(org('ai_pipeline' => 'groq_qwen_vision').scan_pipeline_slug)
      .to eq 'groq_qwen_vision'
  end

  it 'migrates a legacy ai_provider value forward' do
    expect(org('ai_provider' => 'groq').scan_pipeline_slug).to eq 'groq_qwen_vision'
    expect(org('ai_provider' => 'gemini').scan_pipeline_slug).to eq 'groq_qwen_vision'
  end

  it 'prefers an explicit pipeline over a stale legacy value' do
    settings = { 'ai_provider' => 'openrouter', 'ai_pipeline' => 'groq_qwen_vision' }
    expect(org(settings).scan_pipeline_slug).to eq 'groq_qwen_vision'
  end

  it 'falls back to the registry default when nothing is configured' do
    ENV.delete('INVOICE_SCAN_PIPELINE')
    expect(org({}).scan_pipeline_slug)
      .to eq InvoiceScan::Pipelines::Registry::DEFAULT
  end

  it 'honours the server default when the org has no setting' do
    ENV['INVOICE_SCAN_PIPELINE'] = 'groq_llama_scout'
    expect(org({}).scan_pipeline_slug).to eq 'groq_llama_scout'
  end

  it 'returns a usable pipeline object, not just a slug' do
    pipeline = org('ai_pipeline' => 'groq_qwen_vision').scan_pipeline

    expect(pipeline).to be_a InvoiceScan::Pipelines::Base
    expect(pipeline.stages.map { |s| s[:role] }).to eq %i[preprocess extract]
  end

  it 'degrades to the default rather than raising on an unknown slug' do
    expect(org('ai_pipeline' => 'deleted_pipeline').scan_pipeline.slug)
      .to eq InvoiceScan::Pipelines::Registry::DEFAULT
  end
end
