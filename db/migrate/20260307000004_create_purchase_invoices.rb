class CreatePurchaseInvoices < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:purchase_invoices)
    create_table :purchase_invoices do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :supplier,     null: true,  foreign_key: true
      t.references :user,         null: false, foreign_key: true
      t.string     :status,       null: false, default: 'draft'
      t.string     :invoice_number
      t.date       :invoice_date
      t.date       :delivery_date
      t.decimal    :total_taxable_amount, precision: 12, scale: 2, default: 0
      t.decimal    :total_tax_amount,     precision: 12, scale: 2, default: 0
      t.decimal    :total_amount,         precision: 12, scale: 2, default: 0
      t.datetime   :confirmed_at
      t.jsonb      :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :purchase_invoices, :status
    add_index :purchase_invoices, :invoice_date
    add_index :purchase_invoices, :invoice_number
    add_index :purchase_invoices, :metadata, using: :gin
  end
end
