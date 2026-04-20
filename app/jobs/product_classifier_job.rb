class ProductClassifierJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 30.seconds, attempts: 2

  TERMINAL_STATUSES = %w[approved mapped ignored].freeze

  def perform(inbox_item_id)
    inbox_item = ProductInboxItem.find_by(id: inbox_item_id)
    return unless inbox_item
    return if TERMINAL_STATUSES.include?(inbox_item.status)

    inbox_item.update!(status: 'ai_processing')

    result = ProductEnrichmentService.call(
      name:          inbox_item.raw_invoice_text,
      material_code: inbox_item.material_code_hint
    )

    if result[:success]
      inbox_item.update!(
        ai_enrichment: result[:data],
        status:        'pending'
      )
    else
      inbox_item.update!(
        ai_enrichment: { 'error' => result[:error] },
        status:        'needs_review'
      )
    end

    begin
      Turbo::StreamsChannel.broadcast_replace_to(
        "product_inbox_#{inbox_item.organisation_id}",
        target:  "inbox_item_#{inbox_item.id}",
        partial: 'setup/product_inbox/inbox_item',
        locals:  { item: inbox_item.reload }
      )
    rescue => e
      Rails.logger.warn "[ProductClassifierJob] Broadcast failed for inbox_item ##{inbox_item.id}: #{e.message}"
    end
  end
end
