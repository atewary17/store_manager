class CreateProductInboxItems < ActiveRecord::Migration[7.1]
  def change
    create_table :product_inbox_items do |t|
      t.references :organisation,           null: false, foreign_key: true
      t.references :purchase_invoice_item,  null: true,  foreign_key: true
      t.string  :raw_invoice_text,          null: false
      t.string  :material_code_hint
      t.string  :hsn_code_hint
      t.jsonb   :ai_enrichment,             null: false, default: {}
      t.string  :status,                    null: false, default: 'pending'
      t.integer :resolved_product_id,       null: true
      t.integer :resolved_by_id,            null: true
      t.datetime :resolved_at
      t.string  :supplier_name_hint
      t.timestamps
    end

    add_foreign_key :product_inbox_items, :products, column: :resolved_product_id
    add_foreign_key :product_inbox_items, :users,    column: :resolved_by_id

    add_index :product_inbox_items, [:organisation_id, :status]
    add_index :product_inbox_items, [:organisation_id, :raw_invoice_text]
  end
end
