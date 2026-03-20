class AddAdhocAndDiscountToSales < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:sales_invoices, :overall_discount_amount)
      add_column :sales_invoices, :overall_discount_amount, :decimal,
                 precision: 12, scale: 2, default: 0, null: false
    end

    unless column_exists?(:sales_invoice_items, :description)
      add_column :sales_invoice_items, :description, :string
    end
  end
end
