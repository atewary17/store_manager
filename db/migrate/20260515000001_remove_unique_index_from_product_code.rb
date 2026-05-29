class RemoveUniqueIndexFromProductCode < ActiveRecord::Migration[7.1]
  def up
    remove_index :products, name: :index_products_on_product_code
    add_index :products, :product_code, name: :index_products_on_product_code,
              where: "(product_code IS NOT NULL)"
  end

  def down
    remove_index :products, name: :index_products_on_product_code
    add_index :products, :product_code, name: :index_products_on_product_code,
              unique: true, where: "(product_code IS NOT NULL)"
  end
end
