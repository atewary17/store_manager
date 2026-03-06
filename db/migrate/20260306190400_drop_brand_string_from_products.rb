class DropBrandStringFromProducts < ActiveRecord::Migration[7.1]
  def change
    # brand_id FK was already added by CreateBrands migration (20260306000006)
    # Now drop the old free-text brand column
    if column_exists?(:products, :brand)
      remove_column :products, :brand, :string
    end
  end
end
