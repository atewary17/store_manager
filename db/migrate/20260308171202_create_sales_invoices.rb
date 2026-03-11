class CreateSalesInvoices < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_invoices do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :customer,     null: true,  foreign_key: true   # optional walk-in
      t.references :user,         null: false, foreign_key: true

      t.string     :status,           null: false, default: 'draft'   # draft | confirmed
      t.string     :invoice_number
      t.date       :invoice_date
      t.string     :payment_mode                                       # cash | credit | upi | cheque
      t.boolean    :reverse_charge,   null: false, default: false

      t.decimal    :total_taxable_amount, precision: 12, scale: 2, default: 0
      t.decimal    :total_tax_amount,     precision: 12, scale: 2, default: 0
      t.decimal    :total_discount_amount,precision: 12, scale: 2, default: 0
      t.decimal    :total_amount,         precision: 12, scale: 2, default: 0

      t.datetime   :confirmed_at
      t.jsonb      :metadata,  null: false, default: {}
      t.timestamps
    end

    add_index :sales_invoices, :status
    add_index :sales_invoices, :invoice_date
    add_index :sales_invoices, :invoice_number
    add_index :sales_invoices, :payment_mode
    add_index :sales_invoices, :metadata, using: :gin
  end
end
