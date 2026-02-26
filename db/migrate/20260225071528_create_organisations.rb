class CreateOrganisations < ActiveRecord::Migration[7.0]
  def change
    create_table :organisations do |t|
      t.string :name, null: false
      t.string :gst_number
      t.text :address
      t.string :subscription_plan, default: 'basic'
      t.integer :status, default: 0, null: false  # 0 = active, 1 = inactive

      t.timestamps
    end

    add_index :organisations, :gst_number, unique: true
  end
end