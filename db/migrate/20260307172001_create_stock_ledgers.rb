class CreateStockLedgers < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_ledgers do |t|
      t.references :organisation,  null: false, foreign_key: true
      t.references :product,       null: false, foreign_key: true
      t.references :user,          null: false, foreign_key: true
      t.string     :entry_type,    null: false
      t.decimal    :quantity,      null: false, precision: 12, scale: 3
      t.decimal    :unit_cost,     precision: 10, scale: 2
      t.text       :notes
      t.string     :reference_type
      t.bigint     :reference_id
      t.timestamps
    end

    add_index :stock_ledgers, [:organisation_id, :product_id]
    add_index :stock_ledgers, :entry_type
    add_index :stock_ledgers, [:reference_type, :reference_id]
    add_index :stock_ledgers, :created_at
  end
end
