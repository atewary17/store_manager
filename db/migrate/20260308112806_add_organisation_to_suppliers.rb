class AddOrganisationToSuppliers < ActiveRecord::Migration[7.1]
  # This migration exists only for databases that ran the original create_suppliers
  # without organisation_id. On fresh DBs the column already exists via
  # create_suppliers (20260307000003), so we skip everything safely.
  def up
    return unless table_exists?(:suppliers)
    return if column_exists?(:suppliers, :organisation_id)

    add_reference :suppliers, :organisation, null: true, foreign_key: true

    execute <<~SQL
      UPDATE suppliers
      SET organisation_id = (SELECT id FROM organisations ORDER BY id LIMIT 1)
      WHERE organisation_id IS NULL
    SQL

    change_column_null :suppliers, :organisation_id, false

    remove_index :suppliers, :name if index_exists?(:suppliers, :name)
    add_index :suppliers, [:organisation_id, :name], unique: true \
      unless index_exists?(:suppliers, [:organisation_id, :name])
  end

  def down
    return unless column_exists?(:suppliers, :organisation_id)
    remove_index  :suppliers, [:organisation_id, :name] if index_exists?(:suppliers, [:organisation_id, :name])
    add_index     :suppliers, :name unless index_exists?(:suppliers, :name)
    change_column_null :suppliers, :organisation_id, true
    remove_reference   :suppliers, :organisation, foreign_key: true
  end
end
