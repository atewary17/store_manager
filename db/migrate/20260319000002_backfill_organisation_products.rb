# db/migrate/20260319000002_backfill_organisation_products.rb
#
# One-time backfill: enrol every product that has appeared in a purchase invoice
# or sales invoice or stock ledger for each org into organisation_products.
# Safe to re-run — uses INSERT ... ON CONFLICT DO NOTHING.
#
class BackfillOrganisationProducts < ActiveRecord::Migration[7.1]
  def up
    # From purchase invoice items
    execute <<~SQL
      INSERT INTO organisation_products (organisation_id, product_id, active, created_at, updated_at)
      SELECT DISTINCT pi.organisation_id, pii.product_id, true, NOW(), NOW()
      FROM   purchase_invoice_items pii
      JOIN   purchase_invoices pi ON pi.id = pii.purchase_invoice_id
      WHERE  pii.product_id IS NOT NULL
      ON CONFLICT (organisation_id, product_id)
      WHERE  product_id IS NOT NULL
      DO NOTHING
    SQL

    # From sales invoice items
    execute <<~SQL
      INSERT INTO organisation_products (organisation_id, product_id, active, created_at, updated_at)
      SELECT DISTINCT si.organisation_id, sii.product_id, true, NOW(), NOW()
      FROM   sales_invoice_items sii
      JOIN   sales_invoices si ON si.id = sii.sales_invoice_id
      WHERE  sii.product_id IS NOT NULL
      ON CONFLICT (organisation_id, product_id)
      WHERE  product_id IS NOT NULL
      DO NOTHING
    SQL

    # From stock ledgers (catches opening stock entries)
    execute <<~SQL
      INSERT INTO organisation_products (organisation_id, product_id, active, created_at, updated_at)
      SELECT DISTINCT organisation_id, product_id, true, NOW(), NOW()
      FROM   stock_ledgers
      WHERE  product_id IS NOT NULL
      ON CONFLICT (organisation_id, product_id)
      WHERE  product_id IS NOT NULL
      DO NOTHING
    SQL

    total = execute("SELECT COUNT(*) FROM organisation_products").first['count']
    say "Backfilled #{total} organisation_product records"
  end

  def down
    # Do not reverse — would delete all enrolment records
    say "Skipping down — organisation_products data preserved"
  end
end