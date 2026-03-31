# db/migrate/20260326000002_add_gst_fields_to_organisations.rb
# Adds GST-critical fields to organisations so intra/inter-state
# supply type can be determined automatically.
class AddGstFieldsToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :state,      :string unless column_exists?(:organisations, :state)
    add_column :organisations, :state_code, :string unless column_exists?(:organisations, :state_code)
    add_column :organisations, :gstin,      :string unless column_exists?(:organisations, :gstin)
    add_column :organisations, :pan,        :string unless column_exists?(:organisations, :pan)
    add_column :organisations, :address,    :text   unless column_exists?(:organisations, :address)
  end
end