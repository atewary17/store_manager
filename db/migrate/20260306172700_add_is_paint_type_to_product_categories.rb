class AddIsPaintTypeToProductCategories < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:product_categories, :is_paint_type)
      add_column :product_categories, :is_paint_type, :boolean, default: false, null: false
    end
  end
end
