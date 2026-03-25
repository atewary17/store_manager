# db/migrate/20260323000003_add_metadata_to_tinting_machine_canisters.rb
class AddMetadataToTintingMachineCanisters < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:tinting_machine_canisters, :metadata)
    add_column :tinting_machine_canisters, :metadata, :jsonb, null: false, default: {}
    add_index  :tinting_machine_canisters, :metadata, using: :gin
  end
end
