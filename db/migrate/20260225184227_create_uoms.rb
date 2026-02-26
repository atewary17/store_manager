class CreateUoms < ActiveRecord::Migration[7.1]
  def change
    create_table :uoms do |t|
      t.string  :name,       null: false
      t.string  :short_name, null: false
      t.boolean :active,     null: false, default: true

      t.timestamps
    end

    add_index :uoms, :name,       unique: true
    add_index :uoms, :short_name, unique: true
    add_index :uoms, :active
  end
end
