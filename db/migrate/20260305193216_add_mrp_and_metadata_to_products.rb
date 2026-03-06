class AddMrpAndMetadataToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :mrp,      :decimal, precision: 10, scale: 2
    add_column :products, :metadata, :jsonb, default: {}

    add_index :products, :metadata, using: :gin
  end
end