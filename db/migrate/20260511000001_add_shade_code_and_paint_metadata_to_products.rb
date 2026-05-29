class AddShadeCodeAndPaintMetadataToProducts < ActiveRecord::Migration[7.1]
  def up
    add_column :products, :shade_code, :string

    add_index :products, :shade_code,
              name: "idx_products_shade_code_trgm",
              opclass: :gin_trgm_ops,
              using: :gin,
              where: "(shade_code IS NOT NULL)"
  end

  def down
    remove_index :products, name: "idx_products_shade_code_trgm"
    remove_column :products, :shade_code
  end
end
