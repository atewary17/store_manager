class CreateProductImports < ActiveRecord::Migration[7.1]
  def change
    create_table :product_imports do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :user,         null: false, foreign_key: true
      t.string  :file_name,       null: false
      t.integer :file_size,       default: 0
      t.string  :status,          default: 'pending', null: false
      t.integer :total_rows,      default: 0
      t.integer :success_count,   default: 0
      t.integer :update_count,    default: 0
      t.integer :error_count,     default: 0
      t.jsonb   :error_rows,      default: []
      t.text    :file_data        # stores base64 encoded excel for processing
      t.datetime :completed_at
      t.timestamps
    end

    add_index :product_imports, :status
    add_index :product_imports, :created_at
  end
end