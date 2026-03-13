class AddDigitiseToPurchasing < ActiveRecord::Migration[7.1]
  def change
    # ── payment_due_date on purchase_invoices ──────────────────
    unless column_exists?(:purchase_invoices, :payment_due_date)
      add_column :purchase_invoices, :payment_due_date, :date
      add_index  :purchase_invoices, :payment_due_date
    end

    # ── digitise_imports — tracks AI-parsed invoice uploads ────
    create_table :digitise_imports do |t|
      t.bigint   :organisation_id, null: false
      t.bigint   :user_id,         null: false

      # the purchase_invoice this was promoted to (nil until user confirms)
      t.bigint   :purchase_invoice_id

      t.string   :status,    null: false, default: 'pending'
      # pending → processing → review → confirmed → failed

      t.string   :file_name
      t.integer  :file_size
      t.string   :file_content_type   # image/jpeg, image/png, application/pdf
      t.text     :file_data           # base64 encoded — cleared after confirm

      # raw JSON string returned by Gemini
      t.text     :raw_response

      # parsed & user-edited structured data (what gets submitted to DB)
      t.jsonb    :parsed_data,   null: false, default: {}

      # error message if Gemini failed or parse failed
      t.text     :error_message

      t.timestamps
    end

    add_index :digitise_imports, :organisation_id
    add_index :digitise_imports, :user_id
    add_index :digitise_imports, :purchase_invoice_id
    add_index :digitise_imports, :status
  end
end
