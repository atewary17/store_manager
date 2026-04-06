# db/migrate/20260330000001_add_gst_type_columns_to_purchase_invoice_items.rb
#
# Promotes supply_type and per-head GST amounts from metadata jsonb to proper
# columns on purchase_invoice_items.
#
# supply_type: 'intra_state' (CGST+SGST) or 'inter_state' (IGST)
#   → determined at confirm! by comparing organisation.state vs supplier.state
#   → stored in metadata['supply_type'] since the previous migration; promoted here
#
# cgst_amount / sgst_amount / igst_amount: the rupee split per line item
#   → required for accurate ITC reporting per tax head without jsonb parsing
#
# The backfill also RE-DERIVES supply_type for any rows where it was not set
# in metadata, by joining organisations and suppliers and comparing their states.
#
class AddGstTypeColumnsToPurchaseInvoiceItems < ActiveRecord::Migration[7.1]
  def up
    add_column :purchase_invoice_items, :supply_type,  :string,  default: 'intra_state', null: false unless column_exists?(:purchase_invoice_items, :supply_type)
    add_column :purchase_invoice_items, :cgst_amount,  :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:purchase_invoice_items, :cgst_amount)
    add_column :purchase_invoice_items, :sgst_amount,  :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:purchase_invoice_items, :sgst_amount)
    add_column :purchase_invoice_items, :igst_amount,  :decimal, precision: 12, scale: 2, default: 0, null: false unless column_exists?(:purchase_invoice_items, :igst_amount)

    # ── Pass 1: backfill from metadata where supply_type was already stored ──
    # NULLIF guards against empty-string values (same pattern as migration 20260326000001)
    execute <<~SQL
      UPDATE purchase_invoice_items
      SET
        supply_type = COALESCE(
          NULLIF(metadata->>'supply_type', ''),
          'intra_state'
        ),
        cgst_amount = COALESCE(NULLIF(metadata->>'cgst_amount', '')::numeric, 0),
        sgst_amount = COALESCE(NULLIF(metadata->>'sgst_amount', '')::numeric, 0),
        igst_amount = COALESCE(NULLIF(metadata->>'igst_amount', '')::numeric, 0)
      WHERE metadata->>'supply_type' IS NOT NULL
        AND metadata->>'supply_type' != ''
    SQL

    # ── Pass 2: RE-DERIVE supply_type for rows with no metadata supply_type ──
    # Compare organisations.state vs suppliers.state (case-insensitive, trimmed).
    # This handles rows confirmed before supply_type was written to metadata.
    execute <<~SQL
      UPDATE purchase_invoice_items pii
      SET
        supply_type = CASE
          WHEN s.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(s.state)) != TRIM(LOWER(o.state))
          THEN 'inter_state'
          ELSE 'intra_state'
        END,
        cgst_amount = CASE
          WHEN s.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(s.state)) != TRIM(LOWER(o.state))
          THEN 0
          ELSE ROUND(pii.tax_amount / 2.0, 2)
        END,
        sgst_amount = CASE
          WHEN s.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(s.state)) != TRIM(LOWER(o.state))
          THEN 0
          ELSE ROUND(pii.tax_amount / 2.0, 2)
        END,
        igst_amount = CASE
          WHEN s.state IS NOT NULL
            AND o.state IS NOT NULL
            AND TRIM(LOWER(s.state)) != TRIM(LOWER(o.state))
          THEN pii.tax_amount
          ELSE 0
        END
      FROM purchase_invoices pi
      JOIN suppliers s    ON s.id = pi.supplier_id
      JOIN organisations o ON o.id = pi.organisation_id
      WHERE pii.purchase_invoice_id = pi.id
        AND (
          pii.metadata->>'supply_type' IS NULL
          OR pii.metadata->>'supply_type' = ''
        )
    SQL

    add_index :purchase_invoice_items, :supply_type unless index_exists?(:purchase_invoice_items, :supply_type)
  end

  def down
    remove_column :purchase_invoice_items, :supply_type if column_exists?(:purchase_invoice_items, :supply_type)
    remove_column :purchase_invoice_items, :cgst_amount if column_exists?(:purchase_invoice_items, :cgst_amount)
    remove_column :purchase_invoice_items, :sgst_amount if column_exists?(:purchase_invoice_items, :sgst_amount)
    remove_column :purchase_invoice_items, :igst_amount if column_exists?(:purchase_invoice_items, :igst_amount)
  end
end
