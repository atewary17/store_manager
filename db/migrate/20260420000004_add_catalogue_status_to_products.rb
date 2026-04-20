class AddCatalogueStatusToProducts < ActiveRecord::Migration[7.1]
  def up
    add_column :products, :catalogue_status, :string, null: false, default: 'approved'
    add_index  :products, :catalogue_status
    Product.update_all(catalogue_status: 'approved')
  end

  def down
    remove_index  :products, :catalogue_status
    remove_column :products, :catalogue_status
  end
end
