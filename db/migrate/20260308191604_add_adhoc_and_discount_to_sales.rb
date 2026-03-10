class AddAdhocAndDiscountToSales < ActiveRecord::Migration[7.1]
  def change
    # Overall invoice-level discount
    add_column :sales_invoices, :overall_discount_amount, :decimal,
               precision: 12, scale: 2, default: 0, null: false

    # adhoc line type needs a free-text description field
    add_column :sales_invoice_items, :description, :string
  end
end
