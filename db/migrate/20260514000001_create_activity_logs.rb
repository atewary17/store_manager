class CreateActivityLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :activity_logs do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :user,         null: true,  foreign_key: true

      t.string  :activity_type,    null: false
      t.string  :activity_subtype, null: true

      t.text    :description,      null: false

      t.decimal :quantity_litres,  precision: 8, scale: 3, null: true

      t.string  :reference_type,   null: true
      t.bigint  :reference_id,     null: true

      t.jsonb   :metadata,         null: false, default: {}

      t.datetime :expires_at,      null: false

      t.timestamps
    end

    add_index :activity_logs, [:organisation_id, :activity_type, :created_at],
              name: 'idx_activity_logs_org_type_date'
    add_index :activity_logs, [:organisation_id, :created_at],
              name: 'idx_activity_logs_org_date'
    add_index :activity_logs, [:expires_at],
              name: 'idx_activity_logs_expires_at'
    add_index :activity_logs, [:reference_type, :reference_id],
              name: 'idx_activity_logs_reference'
    add_index :activity_logs, [:user_id, :organisation_id, :created_at],
              name: 'idx_activity_logs_user_org_date'
    add_index :activity_logs, [:activity_type],
              name: 'idx_activity_logs_activity_type'
  end
end
