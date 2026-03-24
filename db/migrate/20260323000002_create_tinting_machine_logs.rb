# db/migrate/20260323000002_create_tinting_machine_logs.rb
class CreateTintingMachineLogs < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:tinting_machine_logs)

    create_table :tinting_machine_logs do |t|
      t.references :tinting_machine_canister, null: false, foreign_key: true, index: true
      t.references :organisation,             null: false, foreign_key: true, index: true
      t.references :user,                     null: true,  foreign_key: true, index: true

      t.string     :action,     null: false
                                # loaded | dispensed | refilled | removed | adjusted
      t.decimal    :volume_ml,  null: false, precision: 10, scale: 2
                                # positive = added, negative = used
      t.text       :notes

      t.timestamps
    end
  end
end
