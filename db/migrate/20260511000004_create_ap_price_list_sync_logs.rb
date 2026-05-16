class CreateApPriceListSyncLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :ap_price_list_sync_logs do |t|
      t.references :product,              null: false, foreign_key: true
      t.integer    :ap_price_list_row_id  # nullable — Rule 4 writes a log with no row ref
      t.integer    :rule_applied,         null: false
      t.string     :match_status,         null: false
      t.string     :confidence,           null: false
      t.jsonb      :fields_enriched,      default: []
      t.jsonb      :fields_skipped,       default: {}
      t.jsonb      :match_details,        default: {}
      t.string     :notes
      t.datetime   :run_at,               null: false
      t.bigint     :run_by_id  # null = scheduled, present = manually triggered
      t.timestamps
    end

    add_index :ap_price_list_sync_logs, [:product_id, :run_at]
    add_index :ap_price_list_sync_logs, :match_status
    add_index :ap_price_list_sync_logs, :rule_applied
    add_index :ap_price_list_sync_logs, :run_at
  end
end
