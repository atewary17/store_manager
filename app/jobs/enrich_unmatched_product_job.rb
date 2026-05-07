# app/jobs/enrich_unmatched_product_job.rb
#
# Runs once after PurchaseInvoice#confirm! commits. Calls ProductEnrichmentService
# (Groq AI) to enrich an under_review product with structured metadata, then
# stores the result in product.internet_details.
#
# No retries — each product gets exactly one enrichment attempt. Any failure
# (service error or unexpected exception) is stored in internet_details so the
# SuperAdmin can see what happened, and the job completes without re-raising.

class EnrichUnmatchedProductJob < ApplicationJob
  queue_as :low_priority

  discard_on ActiveRecord::RecordNotFound

  def perform(product_id)
    product = Product.find(product_id)

    # Skip if already enriched or no longer under review
    return unless product.under_review?
    return if product.internet_details_fetched_at.present?

    Rails.logger.info "[EnrichUnmatchedProductJob] Enriching product ##{product_id}: #{product.description}"

    org_id = product.organisation_products.pick(:organisation_id)
    result = ExternalApiLog.record(
      service:         'groq',
      operation:       'product_enrichment',
      organisation_id: org_id,
      metadata:        { product_id: product.id, product_description: product.description,
                         brand_hint: product.brand&.name },
      request_body:    {
        product_name:  product.description,
        material_code: product.material_code,
        brand_hint:    product.brand&.name,
        category_hint: product.product_category&.name,
        hsn_code:      product.hsn_code
      }.compact.to_json
    ) do
      ProductEnrichmentService.call(
        name:          product.description,
        material_code: product.material_code,
        brand_hint:    product.brand&.name
      )
    end

    if result[:success]
      data = result[:data]

      product.update!(
        internet_details:            { 'groq_enrichment' => data },
        internet_details_fetched_at: Time.current
      )

      apply_suggestions(product, data) if data['confidence'].to_f >= 0.75

      Rails.logger.info "[EnrichUnmatchedProductJob] Enriched product ##{product_id} " \
                        "(confidence: #{data['confidence']})"
    else
      Rails.logger.warn "[EnrichUnmatchedProductJob] Enrichment failed for product " \
                        "##{product_id}: #{result[:error]}"
      product.update_columns(
        internet_details:            { 'error' => result[:error] },
        internet_details_fetched_at: Time.current
      )
    end

  rescue StandardError => e
    Rails.logger.error "[EnrichUnmatchedProductJob] Unexpected error for product " \
                       "##{product_id}: #{e.class} — #{e.message}"
    begin
      Product.find(product_id).update_columns(
        internet_details:            { 'error' => "#{e.class}: #{e.message}" },
        internet_details_fetched_at: Time.current
      )
    rescue StandardError
      nil
    end
    # Do not re-raise — job completes cleanly with no retry.
  end

  private

  def apply_suggestions(product, data)
    updates = {}

    if product.brand&.name&.downcase == 'others' && data['brand_guess'].present?
      matched = Brand.match_fuzzy(data['brand_guess'])
      updates[:brand] = matched if matched
    end

    if product.product_category&.name&.downcase == 'others' && data['category_guess'].present?
      matched = ProductCategory.match_fuzzy(data['category_guess'])
      updates[:product_category] = matched if matched
    end

    if data['hsn_code'].present? && product.hsn_code.blank?
      updates[:hsn_code] = data['hsn_code']
    end

    product.update!(updates) if updates.any?
  end
end
