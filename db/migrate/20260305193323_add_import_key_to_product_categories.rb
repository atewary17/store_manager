class AddImportKeyToProductCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :product_categories, :import_key, :string, default: 'material_code'
    add_column :product_categories, :import_key_label, :string, default: 'Material Code'
  end
end