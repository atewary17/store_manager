# db/migrate/20260319000001_create_organisation_products.rb
class CreateOrganisationProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :organisation_products do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :product,      null: true,  foreign_key: true  # nil = org-local product

      # Per-org overrides
      t.decimal :mrp,            precision: 10, scale: 2
      t.boolean :active,         default: true, null: false
      t.string  :internal_code                        # org's own shelf/SKU code
      t.text    :local_description                    # used when product_id is nil
      t.jsonb   :metadata,       default: {}

      t.timestamps
    end

    # An org can only have one entry per master product
    add_index :organisation_products, [:organisation_id, :product_id],
              unique: true,
              where: 'product_id IS NOT NULL',
              name:  'idx_org_products_unique'

    add_index :organisation_products, :active
    add_index :organisation_products, :internal_code
  end
end