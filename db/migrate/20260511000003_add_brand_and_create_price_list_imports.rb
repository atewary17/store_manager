class AddBrandAndCreatePriceListImports < ActiveRecord::Migration[7.1]
  def change
    # 1. Brand linkage on price_list_rows
    add_column :price_list_rows, :brand_id, :bigint
    add_index  :price_list_rows, :brand_id
    add_foreign_key :price_list_rows, :brands, column: :brand_id

    # 2. Import audit log table (mirrors product_imports / shade_catalogue_imports)
    create_table :price_list_imports do |t|
      t.bigint   :user_id, null: false
      t.string   :file_name,   null: false
      t.integer  :file_size,   default: 0
      t.date     :effective_date
      t.integer  :total_rows,   default: 0
      t.integer  :success_count, default: 0   # new rows created
      t.integer  :update_count,  default: 0   # existing rows updated
      t.integer  :skip_count,    default: 0   # skipped (blank / invalid)
      t.integer  :error_count,   default: 0
      t.jsonb    :error_rows,    default: []
      t.datetime :completed_at
      t.timestamps
    end

    add_index :price_list_imports, :user_id
    add_index :price_list_imports, :effective_date
    add_index :price_list_imports, :created_at

    add_foreign_key :price_list_imports, :users
  end
end
