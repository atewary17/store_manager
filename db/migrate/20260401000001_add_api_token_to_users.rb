# db/migrate/20260401000001_add_api_token_to_users.rb
#
# We store a short-lived JWT secret seed per user so that a user's JWT
# can be invalidated server-side by rotating their jti_seed (e.g. on logout
# or password change). This is optional but good practice.
#
# jti = JWT ID claim — a per-user nonce. If you rotate it, all existing
# tokens for that user become invalid immediately even before expiry.

class AddApiTokenToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :jti, :string unless column_exists?(:users, :jti)
    add_index  :users, :jti, unique: true unless index_exists?(:users, :jti)

    # Back-fill existing users with a unique jti
    User.find_each do |u|
      u.update_column(:jti, SecureRandom.hex(24))
    end
  end
end
