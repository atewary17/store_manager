# db/migrate/20260415000001_create_referrers.rb
class CreateReferrers < ActiveRecord::Migration[7.1]
  def change
    create_table :referrers do |t|
      t.references  :organisation, null: false, foreign_key: true
      t.string      :name,         null: false
      t.string      :phone
      t.string      :trade,        null: false, default: 'painter'
      # painter, contractor, electrician, plumber, carpenter, mason, other
      t.string      :address
      t.string      :area          # locality / neighbourhood for easy filtering
      t.boolean     :active,       null: false, default: true
      t.jsonb       :metadata,     null: false, default: {}
      # metadata stores: email, notes, bank details for future commission tracking
      t.timestamps
    end

    add_index :referrers, [:organisation_id, :phone], unique: true,
      where: "phone IS NOT NULL", name: 'idx_referrers_org_phone_unique'
    add_index :referrers, [:organisation_id, :active]
    add_index :referrers, [:organisation_id, :trade]
  end
end
