class CreateStockLevels < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_levels do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :product,      null: false, foreign_key: true
      t.decimal    :quantity,     null: false, precision: 12, scale: 3, default: 0
      t.decimal    :avg_cost,     precision: 10, scale: 2, default: 0
      t.timestamps
    end

    add_index :stock_levels, [:organisation_id, :product_id], unique: true
  end
end
