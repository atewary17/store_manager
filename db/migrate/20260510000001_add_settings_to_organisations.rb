class AddSettingsToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :settings, :jsonb, default: {}, null: false
    add_index  :organisations, :settings, using: :gin, name: 'idx_organisations_settings_gin'
  end
end
