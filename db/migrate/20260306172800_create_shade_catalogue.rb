class CreateShadeCatalogue < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:shade_catalogues)
      create_table :shade_catalogues do |t|
        t.references :product_category, null: false, foreign_key: true
        t.string  :shade_code,    null: false
        t.string  :shade_name,    null: false
        t.string  :manufacturer
        t.string  :colour_family
        t.text    :notes
        t.boolean :active,        null: false, default: true
        t.timestamps
      end

      add_index :shade_catalogues, :shade_code
      add_index :shade_catalogues, [:shade_code, :product_category_id], unique: true, name: 'idx_shade_code_per_category'
      add_index :shade_catalogues, :manufacturer
      add_index :shade_catalogues, :colour_family
      add_index :shade_catalogues, :active
    end
  end
end