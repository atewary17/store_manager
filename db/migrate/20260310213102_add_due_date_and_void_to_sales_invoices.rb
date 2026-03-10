class AddDueDateAndVoidToSalesInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_invoices, :payment_due_date, :date
    add_column :sales_invoices, :voided_at,        :datetime
    add_column :sales_invoices, :voided_by_id,     :bigint

    add_index :sales_invoices, :payment_due_date
    add_index :sales_invoices, :voided_by_id
  end
end
