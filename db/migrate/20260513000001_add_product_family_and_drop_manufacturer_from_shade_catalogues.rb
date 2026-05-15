class AddProductFamilyAndDropManufacturerFromShadeCatalogues < ActiveRecord::Migration[7.1]
  def change
    add_column :shade_catalogues, :product_family, :string
    add_index  :shade_catalogues, :product_family

    remove_index  :shade_catalogues, :manufacturer, if_exists: true
    remove_column :shade_catalogues, :manufacturer, :string
  end
end
