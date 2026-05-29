class AddStatusAndFileDataToPriceListImports < ActiveRecord::Migration[7.1]
  def change
    add_column :price_list_imports, :status,    :string, default: 'pending', null: false
    add_column :price_list_imports, :file_data, :text
    add_index  :price_list_imports, :status
  end
end
