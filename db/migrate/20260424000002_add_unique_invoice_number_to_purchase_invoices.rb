class AddUniqueInvoiceNumberToPurchaseInvoices < ActiveRecord::Migration[7.1]
  def up
    # Remove the old non-unique index first
    remove_index :purchase_invoices, :invoice_number, if_exists: true

    # Unique per organisation — allows blanks (duplicate NULLs are fine in Postgres)
    add_index :purchase_invoices, [:organisation_id, :invoice_number],
              unique: true,
              where:  "invoice_number IS NOT NULL AND invoice_number != ''",
              name:   'idx_purchase_invoices_org_invoice_number_unique'
  end

  def down
    remove_index :purchase_invoices, name: 'idx_purchase_invoices_org_invoice_number_unique', if_exists: true
    add_index :purchase_invoices, :invoice_number
  end
end
