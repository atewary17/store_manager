class CreateProductMergeLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :product_merge_logs do |t|
      # The under_review product that was dissolved
      t.bigint   :merged_product_id,    null: false
      # The confirmed product that absorbed it
      t.bigint   :target_product_id,    null: false
      # Admin who performed the merge
      t.bigint   :performed_by_id,      null: false

      # What was moved
      t.decimal  :stock_transferred,    precision: 12, scale: 4, default: '0.0'
      t.integer  :pi_items_moved,       default: 0, null: false
      t.integer  :ledger_entries_moved, default: 0, null: false
      t.integer  :stock_level_rows_merged, default: 0, null: false

      # Full state of both products captured at merge time (for audit / undo research)
      t.jsonb    :snapshot,             default: {}, null: false

      t.datetime :merged_at,            null: false
      t.timestamps
    end

    add_index :product_merge_logs, :merged_product_id,
              name: 'idx_product_merge_logs_merged'
    add_index :product_merge_logs, :target_product_id,
              name: 'idx_product_merge_logs_target'
    add_index :product_merge_logs, :performed_by_id,
              name: 'idx_product_merge_logs_performed_by'
    add_index :product_merge_logs, :merged_at,
              name: 'idx_product_merge_logs_merged_at'

    # No FK constraints intentionally — merged_product will be deactivated,
    # and we want the log to remain readable even if the product record is
    # eventually hard-deleted.
  end
end
