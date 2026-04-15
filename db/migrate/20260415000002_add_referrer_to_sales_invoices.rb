# db/migrate/20260415000002_add_referrer_to_sales_invoices.rb
class AddReferrerToSalesInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :sales_invoices, :referrer, null: true, foreign_key: true
  end
end
