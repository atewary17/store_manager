# db/migrate/20260320000001_create_purchase_payments.rb
class CreatePurchasePayments < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:purchase_payments)

    create_table :purchase_payments do |t|
      t.references :organisation,     null: false, foreign_key: true
      t.references :purchase_invoice, null: false, foreign_key: true
      t.references :supplier,         null: true,  foreign_key: true
      t.references :user,             null: false, foreign_key: true

      t.date    :payment_date,     null: false
      t.decimal :amount,           null: false, precision: 12, scale: 2
      t.string  :payment_mode,     null: false, default: 'bank_transfer'
      t.string  :reference_number  # UTR / cheque number / transaction ID
      t.string  :payment_number    # PP-YYYYMMDD-0001
      t.text    :notes
      t.jsonb   :metadata,         null: false, default: {}

      t.timestamps
    end

    add_index :purchase_payments, :payment_date
    add_index :purchase_payments, :payment_mode
    add_index :purchase_payments, :payment_number, unique: true,
              where: 'payment_number IS NOT NULL'
    add_index :purchase_payments, :metadata, using: :gin
  end
end
