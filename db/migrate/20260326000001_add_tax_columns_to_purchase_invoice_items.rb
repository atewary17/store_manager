# db/migrate/20260326000001_add_tax_columns_to_purchase_invoice_items.rb
#
# Promotes GST fields from metadata jsonb → proper decimal columns on
# purchase_invoice_items, matching what sales_invoice_items already has.
#
# Metadata keys migrated:
#   discount_percent → discount_percent  (decimal col)
#   cgst_percent + sgst_percent + igst_percent → gst_rate (single rate)
#   taxable_amount  → taxable_amount  (decimal col)
#   cgst_amount + sgst_amount + igst_amount → tax_amount (decimal col)
#
# The metadata keys are NOT removed — they stay as-is for backwards compat.
# The new columns become the source of truth going forward.
#
class AddTaxColumnsToPurchaseInvoiceItems < ActiveRecord::Migration[7.1]
  def up
    add_column :purchase_invoice_items, :gst_rate,        :decimal, precision: 5,  scale: 2, default: 0,    null: false unless column_exists?(:purchase_invoice_items, :gst_rate)
    add_column :purchase_invoice_items, :taxable_amount,  :decimal, precision: 12, scale: 2, default: 0,    null: false unless column_exists?(:purchase_invoice_items, :taxable_amount)
    add_column :purchase_invoice_items, :tax_amount,      :decimal, precision: 12, scale: 2, default: 0,    null: false unless column_exists?(:purchase_invoice_items, :tax_amount)
    add_column :purchase_invoice_items, :discount_percent,:decimal, precision: 5,  scale: 2, default: 0,    null: false unless column_exists?(:purchase_invoice_items, :discount_percent)
    add_column :purchase_invoice_items, :discount_amount, :decimal, precision: 12, scale: 2, default: 0,    null: false unless column_exists?(:purchase_invoice_items, :discount_amount)

    # ── Backfill from metadata ────────────────────────────────────────────────
    # Use raw SQL for performance — avoids loading every AR object.
    # NULLIF(x, '') converts empty-string metadata values to NULL before
    # casting to numeric, preventing PG::InvalidTextRepresentation errors.
    execute <<~SQL
      UPDATE purchase_invoice_items
      SET
        gst_rate = COALESCE(
          -- prefer the single gst_rate stored by new form logic
          NULLIF(metadata->>'gst_rate', '')::numeric,
          -- fall back to cgst+sgst+igst sum from old logic
          COALESCE(NULLIF(metadata->>'cgst_percent', '')::numeric, 0)
          + COALESCE(NULLIF(metadata->>'sgst_percent', '')::numeric, 0)
          + COALESCE(NULLIF(metadata->>'igst_percent', '')::numeric, 0),
          0
        ),
        taxable_amount = COALESCE(
          NULLIF(metadata->>'taxable_amount', '')::numeric,
          0
        ),
        tax_amount = COALESCE(
          COALESCE(NULLIF(metadata->>'cgst_amount', '')::numeric, 0)
          + COALESCE(NULLIF(metadata->>'sgst_amount', '')::numeric, 0)
          + COALESCE(NULLIF(metadata->>'igst_amount', '')::numeric, 0),
          0
        ),
        discount_percent = COALESCE(
          NULLIF(metadata->>'discount_percent', '')::numeric,
          0
        ),
        -- discount_amount = total_amount / (1 - disc/100) * (disc/100)
        -- only meaningful when discount_percent > 0
        discount_amount = CASE
          WHEN COALESCE(NULLIF(metadata->>'discount_percent', '')::numeric, 0) > 0
          THEN ROUND(
            (total_amount
              / (1 - COALESCE(NULLIF(metadata->>'discount_percent', '')::numeric, 0) / 100.0)
            )
            * (COALESCE(NULLIF(metadata->>'discount_percent', '')::numeric, 0) / 100.0),
            2
          )
          ELSE 0
        END
    SQL

    # For rows whose taxable_amount is still 0 (unconfirmed invoices,
    # or old rows where confirm! was never run), derive from total_amount + gst_rate
    execute <<~SQL
      UPDATE purchase_invoice_items
      SET
        taxable_amount = CASE
          WHEN gst_rate > 0
          THEN ROUND(total_amount / (1 + gst_rate / 100.0), 2)
          ELSE total_amount
        END,
        tax_amount = CASE
          WHEN gst_rate > 0
          THEN ROUND(total_amount - (total_amount / (1 + gst_rate / 100.0)), 2)
          ELSE 0
        END
      WHERE taxable_amount = 0 AND total_amount > 0
    SQL

    add_index :purchase_invoice_items, :gst_rate      unless index_exists?(:purchase_invoice_items, :gst_rate)
    add_index :purchase_invoice_items, :taxable_amount unless index_exists?(:purchase_invoice_items, :taxable_amount)
  end

  def down
    remove_column :purchase_invoice_items, :gst_rate         if column_exists?(:purchase_invoice_items, :gst_rate)
    remove_column :purchase_invoice_items, :taxable_amount    if column_exists?(:purchase_invoice_items, :taxable_amount)
    remove_column :purchase_invoice_items, :tax_amount        if column_exists?(:purchase_invoice_items, :tax_amount)
    remove_column :purchase_invoice_items, :discount_percent  if column_exists?(:purchase_invoice_items, :discount_percent)
    remove_column :purchase_invoice_items, :discount_amount   if column_exists?(:purchase_invoice_items, :discount_amount)
  end
end