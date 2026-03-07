class CreateBrands < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:brands)
      create_table :brands do |t|
        t.string  :name,         null: false
        t.string  :short_name
        t.text    :description
        t.boolean :active,       null: false, default: true
        t.timestamps
      end

      add_index :brands, :name,   unique: true
      add_index :brands, :active
    end

    # Add brand_id to products (replaces free-text brand column)
    unless column_exists?(:products, :brand_id)
      add_reference :products, :brand, foreign_key: true, null: true
    end

    # Add brand_id to shade_catalogues (replaces free-text manufacturer column)
    unless column_exists?(:shade_catalogues, :brand_id)
      add_reference :shade_catalogues, :brand, foreign_key: true, null: true
    end
  end
end
