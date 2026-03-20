class CreateSalesInvoiceItems < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:sales_invoice_items)
    create_table :sales_invoice_items do |t|
      t.references :sales_invoice,    null: false, foreign_key: true
      t.references :product,          null: true,  foreign_key: true   # the base/tinter product
      t.references :shade_catalogue,  null: true,  foreign_key: true   # paint items only

      # Line type: 'product' (non-paint) | 'paint' (shade-based, deducts base + tinter)
      t.string     :line_type,        null: false, default: 'product'

      t.decimal    :quantity,         null: false, precision: 12, scale: 3
      t.decimal    :unit_rate,        null: false, precision: 10, scale: 4, default: 0
      t.decimal    :discount_percent, null: false, precision: 5,  scale: 2, default: 0
      t.decimal    :taxable_amount,   null: false, precision: 12, scale: 2, default: 0
      t.decimal    :tax_amount,       null: false, precision: 12, scale: 2, default: 0
      t.decimal    :total_amount,     null: false, precision: 12, scale: 2, default: 0

      # Paint-specific: base product & tinter product deducted from stock separately
      t.references :base_product,     null: true,  foreign_key: { to_table: :products }
      t.references :tinter_product,   null: true,  foreign_key: { to_table: :products }

      t.jsonb      :metadata,  null: false, default: {}
      # metadata stores: cgst_percent, sgst_percent, cgst_amount, sgst_amount,
      #                  shade_code, shade_name, colour_family, base_volume, tinter_volume
      t.timestamps
    end

    add_index :sales_invoice_items, :line_type
    add_index :sales_invoice_items, :metadata, using: :gin
  end
end
