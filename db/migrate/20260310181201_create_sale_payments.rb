class CreateSalePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :sale_payments do |t|
      t.references :organisation,   null: false, foreign_key: true
      t.references :sales_invoice,  null: false, foreign_key: true
      t.references :customer,       null: true,  foreign_key: true   # denormalised for fast creditor queries
      t.references :user,           null: false, foreign_key: true   # recorded by

      t.date       :payment_date,   null: false
      t.decimal    :amount,         null: false, precision: 12, scale: 2
      t.string     :payment_mode,   null: false, default: 'cash'     # cash|upi|cheque|bank_transfer
      t.string     :reference_number                                  # cheque / UTR number
      t.text       :notes
      t.string     :receipt_number                                    # auto-generated on save

      t.jsonb      :metadata,       null: false, default: {}
      t.timestamps
    end

    add_index :sale_payments, :payment_date
    add_index :sale_payments, :payment_mode
    add_index :sale_payments, :receipt_number, unique: true, where: "receipt_number IS NOT NULL"
    add_index :sale_payments, :metadata, using: :gin
  end
end
