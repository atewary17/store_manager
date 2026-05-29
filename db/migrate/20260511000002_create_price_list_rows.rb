class CreatePriceListRows < ActiveRecord::Migration[7.1]
  def change
    create_table :price_list_rows do |t|
      t.string  :product_base_name, null: false
      t.string  :prod_code
      t.string  :shade_name
      t.string  :shade_code
      t.integer :dpl_group
      t.decimal :pack_size_litres, precision: 8, scale: 3
      t.string  :pack_code
      t.decimal :dealer_price,     precision: 10, scale: 2, null: false
      t.date    :effective_date,   null: false
      t.bigint  :matched_product_id
      t.string  :match_status, null: false, default: 'pending'
      t.datetime :imported_at
      t.datetime :matched_at
      t.timestamps
    end

    add_index :price_list_rows, :match_status
    add_index :price_list_rows, :matched_product_id
    add_index :price_list_rows, :effective_date
    add_index :price_list_rows, :shade_code
    add_index :price_list_rows, [:prod_code, :shade_code, :pack_code, :effective_date],
              name: 'idx_price_list_rows_lookup'

    add_foreign_key :price_list_rows, :products, column: :matched_product_id
  end
end
