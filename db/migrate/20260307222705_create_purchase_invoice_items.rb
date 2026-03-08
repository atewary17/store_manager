class CreatePurchaseInvoiceItems < ActiveRecord::Migration[7.1]
  def change
    create_table :purchase_invoice_items do |t|
      t.references :purchase_invoice, null: false, foreign_key: true
      t.references :product,          null: true,  foreign_key: true
      t.boolean    :unmatched,        null: false, default: false
      t.decimal    :quantity,         null: false, precision: 12, scale: 3
      t.decimal    :unit_rate,        null: false, precision: 10, scale: 2
      t.decimal    :total_amount,     null: false, precision: 12, scale: 2
      t.jsonb      :metadata,         null: false, default: {}
      t.timestamps
    end

    add_index :purchase_invoice_items, :unmatched
    add_index :purchase_invoice_items, :metadata, using: :gin
  end
end
