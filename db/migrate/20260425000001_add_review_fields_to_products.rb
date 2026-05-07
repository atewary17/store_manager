class AddReviewFieldsToProducts < ActiveRecord::Migration[7.1]
  def up
    # ── New columns ──────────────────────────────────────────────────────────
    add_column :products, :under_review,                :boolean,  default: false, null: false
    add_column :products, :catalogue_status,             :string,   default: 'active', null: false
    # 'active' | 'under_review' | 'merged' | 'rejected'

    add_column :products, :source,                      :string,   default: 'manual'
    # 'manual' | 'import' | 'pi_scan'

    add_column :products, :internet_details,             :jsonb,    default: {}
    add_column :products, :internet_details_fetched_at,  :datetime

    add_column :products, :merged_into_product_id,       :bigint
    add_column :products, :review_notes,                 :text
    add_column :products, :reviewed_at,                  :datetime
    add_column :products, :reviewed_by_id,               :bigint

    # ── Indexes ───────────────────────────────────────────────────────────────
    add_index :products, :under_review,
              where:  'under_review = true',
              name:   'idx_products_under_review'

    add_index :products, :catalogue_status,
              name: 'idx_products_catalogue_status'

    add_index :products, :merged_into_product_id,
              name: 'idx_products_merged_into_product_id'

    add_index :products, :source,
              name: 'idx_products_source'

    add_index :products, :internet_details,
              using: :gin,
              name:  'idx_products_internet_details_gin'

    # Trigram indexes for similarity search
    add_index :products, :description,
              using:   :gin,
              opclass: :gin_trgm_ops,
              name:    'idx_products_description_trgm'

    add_index :products, :material_code,
              using:   :gin,
              opclass: :gin_trgm_ops,
              where:   'material_code IS NOT NULL',
              name:    'idx_products_material_code_trgm'

    # ── Relax material_code uniqueness to allow duplicates while under review ─
    # Original index enforces uniqueness for all non-null material_codes.
    # Under_review products (created from scans before admin approval) may share
    # a material_code with existing products until the merge/approve step resolves them.
    remove_index :products, name: 'index_products_on_material_code'
    add_index :products, :material_code,
              unique: true,
              where:  '(material_code IS NOT NULL AND under_review = false)',
              name:   'idx_products_material_code_unique_confirmed'

    # ── Foreign keys ─────────────────────────────────────────────────────────
    add_foreign_key :products, :users,    column: :reviewed_by_id
    add_foreign_key :products, :products, column: :merged_into_product_id
  end

  def down
    remove_foreign_key :products, column: :reviewed_by_id
    remove_foreign_key :products, column: :merged_into_product_id

    remove_index :products, name: 'idx_products_under_review'
    remove_index :products, name: 'idx_products_catalogue_status'
    remove_index :products, name: 'idx_products_merged_into_product_id'
    remove_index :products, name: 'idx_products_source'
    remove_index :products, name: 'idx_products_internet_details_gin'
    remove_index :products, name: 'idx_products_description_trgm'
    remove_index :products, name: 'idx_products_material_code_trgm'
    remove_index :products, name: 'idx_products_material_code_unique_confirmed'

    # Restore original unique index
    add_index :products, :material_code,
              unique: true,
              where:  '(material_code IS NOT NULL)',
              name:   'index_products_on_material_code'

    remove_column :products, :under_review
    remove_column :products, :catalogue_status
    remove_column :products, :source
    remove_column :products, :internet_details
    remove_column :products, :internet_details_fetched_at
    remove_column :products, :merged_into_product_id
    remove_column :products, :review_notes
    remove_column :products, :reviewed_at
    remove_column :products, :reviewed_by_id
  end
end
