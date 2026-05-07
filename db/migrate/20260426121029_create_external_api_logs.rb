class CreateExternalApiLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :external_api_logs do |t|
      t.string   :service,       null: false              # 'groq', 'openrouter', etc.
      t.string   :operation,     null: false              # 'invoice_parse', 'product_enrichment'
      t.string   :status,        null: false, default: 'pending'  # pending/success/error
      t.integer  :http_status                             # HTTP response code
      t.float    :duration_ms                             # round-trip ms
      t.text     :request_body                            # truncated request payload
      t.text     :response_body                           # truncated raw response
      t.text     :error_message
      t.jsonb    :metadata,      default: {}              # reference IDs, hints, etc.
      t.bigint   :organisation_id
      t.bigint   :user_id
      t.timestamps
    end

    add_index :external_api_logs, :service
    add_index :external_api_logs, :operation
    add_index :external_api_logs, :status
    add_index :external_api_logs, :created_at
    add_index :external_api_logs, :organisation_id
  end
end
