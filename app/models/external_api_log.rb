# app/models/external_api_log.rb
class ExternalApiLog < ApplicationRecord

  belongs_to :organisation, optional: true
  belongs_to :user,         optional: true

  STATUSES   = %w[pending success error].freeze
  SERVICES   = %w[groq openrouter mock].freeze
  OPERATIONS = %w[invoice_parse product_enrichment].freeze

  scope :recent,    -> { order(created_at: :desc) }
  scope :succeeded, -> { where(status: 'success') }
  scope :failed,    -> { where(status: 'error') }
  scope :for_service,   ->(s) { where(service: s) }
  scope :for_operation, ->(o) { where(operation: o) }

  MAX_BODY_LENGTH = 8_000

  # Central entry point — call from any service that hits an external API.
  # Yields to the block, records timing, status, and response automatically.
  #
  # ExternalApiLog.record(service: 'groq', operation: 'invoice_parse',
  #                        organisation_id: org.id, metadata: { import_id: 5 }) do
  #   # make the API call, return { success:, raw_response:, error:, http_status: }
  # end
  def self.record(service:, operation:, organisation_id: nil, user_id: nil, metadata: {}, request_body: nil)
    log = create!(
      service:         service,
      operation:       operation,
      status:          'pending',
      organisation_id: organisation_id,
      user_id:         user_id,
      metadata:        metadata,
      request_body:    request_body.to_s.truncate(MAX_BODY_LENGTH)
    )

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result     = nil

    begin
      result = yield
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

      log.update!(
        status:        result[:success] ? 'success' : 'error',
        http_status:   result[:http_status],
        duration_ms:   elapsed,
        response_body: result[:raw_response].to_s.truncate(MAX_BODY_LENGTH),
        error_message: result[:error]
      )
    rescue => e
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
      log.update!(status: 'error', duration_ms: elapsed, error_message: e.message)
      raise
    end

    result
  end

  def success?  = status == 'success'
  def failed?   = status == 'error'
  def pending?  = status == 'pending'

  def duration_label
    return '—' if duration_ms.nil?
    duration_ms >= 1000 ? "#{(duration_ms / 1000.0).round(2)}s" : "#{duration_ms.round}ms"
  end
end
