class CreateCustomers < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:customers)
    create_table :customers do |t|
      t.references :organisation, null: false, foreign_key: true
      t.string  :name,        null: false
      t.string  :phone
      t.string  :gstin
      t.string  :pan
      t.string  :state
      t.string  :state_code
      t.boolean :active,      null: false, default: true
      t.jsonb   :metadata,    null: false, default: {}   # address, email, credit_limit etc.
      t.timestamps
    end

    add_index :customers, [:organisation_id, :name]
    add_index :customers, :gstin
    add_index :customers, :phone
    add_index :customers, :active
    add_index :customers, :metadata, using: :gin
  end
end
