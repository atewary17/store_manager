# app/models/digitise_import_job.rb
class DigitiseImportJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 1

  def perform(digitise_import_id)
    import = DigitiseImport.find_by(id: digitise_import_id)
    return unless import
    return if %w[review confirmed stopped].include?(import.status)
    return unless %w[pending processing retrying].include?(import.status)

    attempt_num = import.attempt_count + 1
    import.update!(status: 'processing', attempt_count: attempt_num)

    base64_data   = import.file_data.to_s.gsub(/\s+/, '')
    user_pref     = import.user&.preferences&.dig('ai_provider').presence
    supplier_hint = import.parsed_data&.dig('supplier', 'name').presence

    # The organisation's configured scanning process decides what runs. A user
    # preference is only honoured for super admins — see InvoiceAiService.
    provider = import.organisation&.scan_pipeline_slug ||
               InvoiceScan::Pipelines::Registry::DEFAULT

    result = ExternalApiLog.record(
      service:         provider,
      operation:       'invoice_parse',
      organisation_id: import.organisation_id,
      user_id:         import.user_id,
      metadata:        { digitise_import_id: import.id, file_name: import.file_name,
                         attempt: attempt_num, supplier_hint: supplier_hint }
    ) do
      InvoiceAiService.call(
        base64_data:   base64_data,
        mime_type:     import.file_content_type,
        user_pref:     user_pref,
        supplier_hint: supplier_hint,
        organisation:  import.organisation,
        user:          import.user
      )
    end

    log_entry = {
      attempt:  attempt_num,
      at:       Time.current.iso8601,
      success:  result[:success],
      error:    result[:error],
      response: result[:raw_response].to_s.truncate(2000)
    }
    new_log = (import.attempt_log || []) + [log_entry]

    if result[:success]
      meta = result.dig(:data, '_meta') || {}

      import.update!(
        status:         'review',
        parsed_data:    result[:data],
        raw_response:   result[:raw_response],
        error_message:  nil,
        attempt_log:    new_log,
        # Records the pipeline slug that actually ran, so an import can always
        # show what read it — including after that pipeline is retired.
        ai_provider:    result[:provider] || provider,
        page_count:     meta['page_count'].presence || 1,
        pages_scanned:  meta['pages_scanned'].presence || 1,
        preview_image:  result[:preview_image]   # base64 JPEG of page 1, nil for plain images
      )
    else
      is_rate_limit = result[:error].to_s.include?('429')
      can_retry     = is_rate_limit && attempt_num < MAX_ATTEMPTS

      import.update!(
        status:        can_retry ? 'pending' : 'failed',
        raw_response:  result[:raw_response].to_s,
        error_message: result[:error],
        attempt_log:   new_log
      )

      if can_retry
        import.update!(status: 'retrying')
        DigitiseImportJob.set(wait: 65.seconds).perform_later(import.id)
      end
    end

  rescue => e
    log_entry = {
      attempt:  import&.attempt_count.to_i,
      at:       Time.current.iso8601,
      success:  false,
      error:    "Job error: #{e.message}",
      response: nil
    }
    new_log = ((import&.attempt_log) || []) + [log_entry]
    import&.update!(
      status:        'failed',
      error_message: "Job error: #{e.message}",
      attempt_log:   new_log
    )
    raise
  end
end
