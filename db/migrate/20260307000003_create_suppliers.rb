class CreateSuppliers < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:suppliers)
    create_table :suppliers do |t|
      t.references :organisation, null: false, foreign_key: true
      t.string  :name,       null: false
      t.string  :gstin
      t.string  :pan
      t.string  :state
      t.string  :state_code
      t.boolean :active,     null: false, default: true
      t.jsonb   :metadata,   null: false, default: {}
      t.timestamps
    end

    # Name unique per organisation, not globally
    add_index :suppliers, [:organisation_id, :name], unique: true
    add_index :suppliers, :gstin
    add_index :suppliers, :active
    add_index :suppliers, :metadata, using: :gin
  end
end
