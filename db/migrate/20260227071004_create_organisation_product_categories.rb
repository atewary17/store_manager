class CreateOrganisationProductCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :organisation_product_categories do |t|
      t.references :organisation,      null: false, foreign_key: true
      t.references :product_category,  null: false, foreign_key: true
      t.timestamps
    end

    add_index :organisation_product_categories,
              [:organisation_id, :product_category_id],
              unique: true,
              name: 'idx_org_product_categories_unique'
  end
end
