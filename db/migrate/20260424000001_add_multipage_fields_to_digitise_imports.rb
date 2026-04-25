class AddMultipageFieldsToDigitiseImports < ActiveRecord::Migration[7.1]
  def change
    add_column :digitise_imports, :session_id,     :string,  null: true, comment: 'UUID grouping multiple uploads of the same invoice'
    add_column :digitise_imports, :page_count,     :integer, null: true, comment: 'Total pages the AI detected in the uploaded file'
    add_column :digitise_imports, :pages_scanned,  :integer, null: true, comment: 'Number of pages actually sent to AI'
    add_column :digitise_imports, :preview_image,  :text,    null: true, comment: 'Base64 JPEG of page 1 for the review preview panel'

    add_index :digitise_imports, :session_id
  end
end
