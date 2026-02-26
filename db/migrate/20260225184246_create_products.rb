class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.references :product_category, null: false, foreign_key: true
      t.references :base_uom,         null: false, foreign_key: { to_table: :uoms }

      t.string  :brand,         null: false
      t.string  :material_code
      t.string  :product_code
      t.string  :pack_code
      t.text    :description
      t.string  :hsn_code
      t.decimal :gst_rate,      precision: 5, scale: 2, null: false, default: 0.0
      t.boolean :active,        null: false, default: true

      t.timestamps
    end

    # t.references above already creates indexes on product_category_id and base_uom_id
    add_index :products, :brand
    add_index :products, :material_code, unique: true, where: "material_code IS NOT NULL"
    add_index :products, :product_code,  unique: true, where: "product_code IS NOT NULL"
    add_index :products, :hsn_code
    add_index :products, :active
  end
end
