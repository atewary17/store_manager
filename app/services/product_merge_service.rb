# app/services/product_merge_service.rb
#
# Merges an under_review product into an existing active product.
# All purchase invoice items, sales invoice items, stock ledger entries,
# stock levels, and organisation enrolments are re-pointed to the target.
#
# IMPORTANT: StockLedger is append-only (before_update raises ReadOnlyRecord).
# We use update_all (raw SQL, bypasses AR callbacks) to re-point ledger rows,
# then recalculate StockLevel from the ledger directly.
#
# Usage:
#   result = ProductMergeService.call(
#     under_review_product: product,
#     target_product:       existing_product,
#     performed_by:         current_user
#   )
#   result # => { success: true } or { success: false, error: "..." }

class ProductMergeService

  def self.call(under_review_product:, target_product:, performed_by:)
    new(
      under_review_product: under_review_product,
      target_product:       target_product,
      performed_by:         performed_by
    ).call
  end

  def initialize(under_review_product:, target_product:, performed_by:)
    @source      = under_review_product
    @target      = target_product
    @by          = performed_by
  end

  def call
    validate!

    # Snapshot both products before touching anything
    snapshot = {
      'under_review' => @source.as_json,
      'target'       => @target.as_json
    }

    # Gather counts before the merge (for the audit log)
    pi_items_count     = PurchaseInvoiceItem.where(product_id: @source.id).count
    si_items_count     = SalesInvoiceItem.where(product_id: @source.id).count
    ledger_count       = StockLedger.where(product_id: @source.id).count
    stock_transferred  = StockLedger.where(product_id: @source.id, entry_type: 'purchase').sum(:quantity).to_f
    stock_level_orgs   = StockLevel.where(product_id: @source.id).pluck(:organisation_id)

    ActiveRecord::Base.transaction do
      # 1. Re-point purchase invoice items
      PurchaseInvoiceItem.where(product_id: @source.id)
                         .update_all(product_id: @target.id)

      # 2. Re-point sales invoice items (safety — should be empty since product was inactive)
      SalesInvoiceItem.where(product_id: @source.id)
                      .update_all(product_id: @target.id)

      # 3. Re-point stock ledger entries.
      #    update_all is raw SQL — bypasses the before_update ReadOnlyRecord guard.
      #    Historical audit trail is preserved, just under the target product.
      StockLedger.where(product_id: @source.id)
                 .update_all(product_id: @target.id)

      # 4. Recalculate StockLevel for both products in every affected org.
      #    Delete source's level (now empty); rebuild target's level from ledger.
      StockLevel.where(product_id: @source.id).delete_all

      stock_level_orgs.each do |org_id|
        recalculate_stock_level!(org_id, @target.id)
      end

      # 5. Move OrganisationProduct enrolments
      OrganisationProduct.where(product_id: @source.id).each do |op|
        OrganisationProduct.find_or_create_by!(
          organisation_id: op.organisation_id,
          product_id:      @target.id
        )
        op.destroy!
      end

      # 6. Audit log
      ProductMergeLog.create!(
        merged_product_id:       @source.id,
        target_product_id:       @target.id,
        performed_by_id:         @by.id,
        stock_transferred:       stock_transferred,
        pi_items_moved:          pi_items_count + si_items_count,
        ledger_entries_moved:    ledger_count,
        stock_level_rows_merged: stock_level_orgs.size,
        snapshot:                snapshot,
        merged_at:               Time.current
      )

      # 7. Deactivate the source product
      @source.update_columns(
        active:                  false,
        under_review:            false,
        catalogue_status:        'merged',
        merged_into_product_id:  @target.id
      )
    end

    { success: true }

  rescue ArgumentError => e
    { success: false, error: e.message }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  rescue => e
    Rails.logger.error "[ProductMergeService] Unexpected error: #{e.class} — #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    { success: false, error: "Merge failed: #{e.message}" }
  end

  private

  def validate!
    raise ArgumentError, 'Source product must be under_review'  unless @source.under_review?
    raise ArgumentError, 'Cannot merge a product into itself'   if @source.id == @target.id
    raise ArgumentError, 'Target product must be active'        unless @target.active?
    raise ArgumentError, 'Target cannot be under_review'        if @target.under_review?
  end

  # Recalculates the StockLevel row for a product in one org by summing
  # the ledger. Handles weighted avg_cost for purchase entries.
  def recalculate_stock_level!(org_id, product_id)
    entries = StockLedger.where(organisation_id: org_id, product_id: product_id)

    total_qty = entries.sum(:quantity).to_f

    purchase_entries = entries.where(entry_type: 'purchase').where('unit_cost > 0')
    total_value      = purchase_entries.sum('quantity * unit_cost').to_f
    total_purchased  = purchase_entries.sum(:quantity).to_f
    avg_cost         = total_purchased > 0 ? (total_value / total_purchased).round(4) : 0.0

    level = StockLevel.find_or_initialize_by(
      organisation_id: org_id,
      product_id:      product_id
    )
    level.quantity = total_qty
    level.avg_cost = avg_cost
    level.save!
  end

end
