# db/migrate/20260323000001_create_tinting_machine_canisters.rb
class CreateTintingMachineCanisters < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:tinting_machine_canisters)

    create_table :tinting_machine_canisters do |t|
      t.references :organisation,  null: false, foreign_key: true, index: true
      t.references :brand,         null: false, foreign_key: true, index: true
      t.references :product,       null: true,  foreign_key: true, index: true
      t.references :loaded_by,     null: true,  foreign_key: { to_table: :users }, index: true

      t.integer    :slot_number,          null: false          # 1–16
      t.integer    :initial_volume_ml,    null: false          # volume when can was loaded
      t.string     :status,               null: false, default: 'empty'
                                          # empty | active | low | critical
      t.decimal    :dispensed_volume_ml,  null: false, default: 0, precision: 10, scale: 2
      t.datetime   :loaded_at
      t.text       :notes

      t.timestamps
    end

    add_index :tinting_machine_canisters,
              [:organisation_id, :brand_id, :slot_number],
              unique: true,
              name: 'idx_tinting_canisters_org_brand_slot'
  end
end
