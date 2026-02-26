class DeviseCreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.integer  :organisation_id
      t.string   :email, null: false, default: ""
      t.string   :encrypted_password, null: false, default: ""
      t.integer  :role, default: 0, null: false      # 0=staff, 1=admin, 2=owner, 3=super_admin
      t.integer  :status, default: 0, null: false    # 0=active, 1=inactive

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :organisation_id
  end
end