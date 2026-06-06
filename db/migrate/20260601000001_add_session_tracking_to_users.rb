class AddSessionTrackingToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :session_token,    :string
    add_column :users, :last_activity_at, :datetime
    add_index  :users, :session_token, unique: true
  end
end
