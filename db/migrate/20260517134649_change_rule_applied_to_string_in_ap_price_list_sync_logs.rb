class ChangeRuleAppliedToStringInApPriceListSyncLogs < ActiveRecord::Migration[7.1]
  def up
    remove_index :ap_price_list_sync_logs, :rule_applied, if_exists: true
    change_column :ap_price_list_sync_logs, :rule_applied, :string, null: false, default: 'NMPL',
                  using: "rule_applied::text"
    add_index :ap_price_list_sync_logs, :rule_applied
  end

  def down
    remove_index :ap_price_list_sync_logs, :rule_applied, if_exists: true
    change_column :ap_price_list_sync_logs, :rule_applied, :integer, null: false, default: 0,
                  using: "rule_applied::integer"
    add_index :ap_price_list_sync_logs, :rule_applied
  end
end
