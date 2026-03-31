# db/migrate/20260331000001_create_gst_credit_ledger.rb
#
# Stores the CLOSING Electronic Credit Ledger balance per organisation
# per calendar month. Once a month is "closed" (user clicks Finalise),
# the balances carry forward as the next month's opening balance.
#
# Schema mirrors the GST portal's Electronic Credit Ledger:
#   igst_balance, cgst_balance, sgst_balance — unused ITC at month end
#
# Workflow:
#   1. User views GSTR-3B for, say, Feb 2026.
#   2. System fetches Feb opening balance from this table (Jan 2026 closing).
#   3. Adds Feb's new ITC from purchase invoices.
#   4. Runs 7-step set-off against Feb's output tax.
#   5. User clicks "Close Period" → saves Feb's closing balance here.
#   6. March GSTR-3B automatically picks up Feb's closing as opening.
#
class CreateGstCreditLedger < ActiveRecord::Migration[7.1]
  def change
    create_table :gst_credit_ledger_entries do |t|
      t.references  :organisation, null: false, foreign_key: true
      t.integer     :period_year,  null: false
      t.integer     :period_month, null: false

      # Opening balances (carried from prior month's closing)
      t.decimal :opening_igst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :opening_cgst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :opening_sgst, precision: 12, scale: 2, default: 0, null: false

      # ITC earned this period from purchases
      t.decimal :period_igst_itc, precision: 12, scale: 2, default: 0, null: false
      t.decimal :period_cgst_itc, precision: 12, scale: 2, default: 0, null: false
      t.decimal :period_sgst_itc, precision: 12, scale: 2, default: 0, null: false

      # Output tax this period (for audit trail)
      t.decimal :period_igst_out, precision: 12, scale: 2, default: 0, null: false
      t.decimal :period_cgst_out, precision: 12, scale: 2, default: 0, null: false
      t.decimal :period_sgst_out, precision: 12, scale: 2, default: 0, null: false

      # Closing balances = opening + period ITC - utilised
      t.decimal :closing_igst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :closing_cgst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :closing_sgst, precision: 12, scale: 2, default: 0, null: false

      # Cash paid to government this period
      t.decimal :cash_igst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :cash_cgst, precision: 12, scale: 2, default: 0, null: false
      t.decimal :cash_sgst, precision: 12, scale: 2, default: 0, null: false

      t.boolean   :period_closed, default: false, null: false
      t.datetime  :closed_at
      t.references :closed_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end

    add_index :gst_credit_ledger_entries,
              [:organisation_id, :period_year, :period_month],
              unique: true,
              name: 'idx_gst_credit_ledger_unique_period'
  end
end
