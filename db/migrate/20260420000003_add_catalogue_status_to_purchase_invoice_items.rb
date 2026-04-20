class AddCatalogueStatusToPurchaseInvoiceItems < ActiveRecord::Migration[7.1]
  def change
    add_column :purchase_invoice_items, :catalogue_status,      :string,  default: 'matched'
    add_column :purchase_invoice_items, :product_inbox_item_id, :integer, null: true
    add_column :purchase_invoice_items, :stock_held,            :boolean, default: false, null: false

    add_index :purchase_invoice_items, :catalogue_status
  end
end
