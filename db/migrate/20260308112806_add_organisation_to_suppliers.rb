class AddOrganisationToSuppliers < ActiveRecord::Migration[7.1]
  def up
    # Step 1 — add nullable first (can't use subquery as DEFAULT in PG)
    add_reference :suppliers, :organisation, null: true, foreign_key: true

    # Step 2 — backfill: assign every existing supplier to the first organisation.
    # Safe for dev/staging. In production, update this query to match your data.
    execute <<~SQL
      UPDATE suppliers
      SET organisation_id = (SELECT id FROM organisations ORDER BY id LIMIT 1)
      WHERE organisation_id IS NULL
    SQL

    # Step 3 — now enforce NOT NULL
    change_column_null :suppliers, :organisation_id, false

    # Step 4 — replace global name index with per-org unique index
    remove_index :suppliers, :name
    add_index    :suppliers, [:organisation_id, :name], unique: true
  end

  def down
    remove_index  :suppliers, [:organisation_id, :name]
    add_index     :suppliers, :name
    change_column_null :suppliers, :organisation_id, true
    remove_reference   :suppliers, :organisation, foreign_key: true
  end
end
