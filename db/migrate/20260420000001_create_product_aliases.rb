class CreateProductAliases < ActiveRecord::Migration[7.1]
  def change
    create_table :product_aliases do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :product,      null: false, foreign_key: true
      t.string  :raw_text,        null: false
      t.string  :normalised_text, null: false
      t.integer :supplier_id,     null: true
      t.string  :source,          null: false, default: 'exact'
      t.float   :confidence,      null: false, default: 1.0
      t.integer :hit_count,       null: false, default: 0
      t.timestamps
    end

    add_index :product_aliases, [:organisation_id, :normalised_text], unique: true
    add_index :product_aliases, [:organisation_id, :product_id]
  end
end
