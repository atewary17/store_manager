class CreateSuppliers < ActiveRecord::Migration[7.1]
  def change
    create_table :suppliers do |t|
      t.string  :name,       null: false
      t.string  :gstin
      t.string  :pan
      t.string  :state
      t.string  :state_code
      t.boolean :active,     null: false, default: true
      t.jsonb   :metadata,   null: false, default: {}
      t.timestamps
    end

    add_index :suppliers, :name
    add_index :suppliers, :gstin
    add_index :suppliers, :active
    add_index :suppliers, :metadata, using: :gin
  end
end