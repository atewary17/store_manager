# db/migrate/20260330000002_add_gst_type_columns_to_sales_invoice_items.rb
#
# Mirrors what was done for purchase_invoice_items in 20260330000001.
#
# supply_type: 'intra_state' (CGST+SGST) or 'inter_state' (IGST)
#   → determined by comparing organisation.state vs customer.state
#   → previously never computed — all sales were assumed intra-state
#
# gst_rate:    single combined rate (cgst_percent + sgst_percent from metadata)
# cgst_amount: proper column (was metadata only)
# sgst_amount: proper column (was metadata only)
# igst_amount: proper column (was never computed — always 0)
#
# Backfill re-derives supply_type by joining organisations and customers.
#
class AddGstTypeColumnsToSalesInvoiceItems < ActiveRecord::Migration[7.1]
  def up
    add_column :sales_invoice_items, :supply_type, :string,  default: 'intra_state', null: false unless column_exists?(:sales_invoice_items, :supply_type)
    add_column :sales_invoice_items, :gst_rate,    :decimal, precision: 5,  scale: 2, default: 0, null: false unless column_exists?(:sales_invoice_items, :gst_rate)
    add_column :sales_invoice_items, :cgst_amount, :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:sales_invoice_items, :cgst_amount)
    add_column :sales_invoice_items, :sgst_amount, :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:sales_invoice_items, :sgst_amount)
    add_column :sales_invoice_items, :igst_amount, :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:sales_invoice_items, :igst_amount)

    # ── Pass 1: backfill from metadata + state comparison ────────────────────
    # Joins customers and organisations to determine supply_type correctly.
    # NULLIF guards against empty strings in metadata (same as purchase migration).
    execute <<~SQL
      UPDATE sales_invoice_items sii
      SET
        supply_type = CASE
          WHEN c.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(c.state)) != TRIM(LOWER(o.state))
          THEN 'inter_state'
          ELSE 'intra_state'
        END,

        gst_rate = COALESCE(
          NULLIF(sii.metadata->>'cgst_percent', '')::numeric,
          0
        ) + COALESCE(
          NULLIF(sii.metadata->>'sgst_percent', '')::numeric,
          0
        ),

        -- For intra-state: use stored metadata amounts (already calculated by compute_amounts)
        -- For inter-state: full tax_amount becomes IGST (metadata had no igst_amount)
        cgst_amount = CASE
          WHEN c.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(c.state)) != TRIM(LOWER(o.state))
          THEN 0
          ELSE COALESCE(NULLIF(sii.metadata->>'cgst_amount', '')::numeric, ROUND(sii.tax_amount / 2.0, 2))
        END,

        sgst_amount = CASE
          WHEN c.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(c.state)) != TRIM(LOWER(o.state))
          THEN 0
          ELSE COALESCE(NULLIF(sii.metadata->>'sgst_amount', '')::numeric, ROUND(sii.tax_amount / 2.0, 2))
        END,

        igst_amount = CASE
          WHEN c.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(c.state)) != TRIM(LOWER(o.state))
          THEN sii.tax_amount
          ELSE 0
        END

      FROM sales_invoices si
      JOIN organisations o  ON o.id  = si.organisation_id
      LEFT JOIN customers c ON c.id  = si.customer_id
      WHERE sii.sales_invoice_id = si.id
    SQL

    # ── Pass 2: rows with no customer (walk-in sales) → intra-state ──────────
    # Already defaulted to 'intra_state' by the CASE above (c.state IS NULL → ELSE),
    # but explicitly fill cgst/sgst from metadata for these rows too.
    execute <<~SQL
      UPDATE sales_invoice_items sii
      SET
        cgst_amount = COALESCE(NULLIF(sii.metadata->>'cgst_amount', '')::numeric, ROUND(sii.tax_amount / 2.0, 2)),
        sgst_amount = COALESCE(NULLIF(sii.metadata->>'sgst_amount', '')::numeric, ROUND(sii.tax_amount / 2.0, 2))
      FROM sales_invoices si
      WHERE sii.sales_invoice_id = si.id
        AND si.customer_id IS NULL
        AND sii.cgst_amount = 0
        AND sii.tax_amount > 0
    SQL

    add_index :sales_invoice_items, :supply_type unless index_exists?(:sales_invoice_items, :supply_type)
    add_index :sales_invoice_items, :gst_rate    unless index_exists?(:sales_invoice_items, :gst_rate)
  end

  def down
    remove_column :sales_invoice_items, :supply_type if column_exists?(:sales_invoice_items, :supply_type)
    remove_column :sales_invoice_items, :gst_rate    if column_exists?(:sales_invoice_items, :gst_rate)
    remove_column :sales_invoice_items, :cgst_amount if column_exists?(:sales_invoice_items, :cgst_amount)
    remove_column :sales_invoice_items, :sgst_amount if column_exists?(:sales_invoice_items, :sgst_amount)
    remove_column :sales_invoice_items, :igst_amount if column_exists?(:sales_invoice_items, :igst_amount)
  end
end
