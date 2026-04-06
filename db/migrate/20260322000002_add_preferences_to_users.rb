# db/migrate/20260322000002_add_preferences_to_users.rb
class AddPreferencesToUsers < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:users, :preferences)
    add_column :users, :preferences, :jsonb, null: false, default: {}
    add_index  :users, :preferences, using: :gin
  end
end
