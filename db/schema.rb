# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_22_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "plpgsql"

  create_table "brands", force: :cascade do |t|
    t.string "name", null: false
    t.string "short_name"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_brands_on_active"
    t.index ["name"], name: "index_brands_on_name", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "gstin"
    t.string "pan"
    t.string "state"
    t.string "state_code"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_customers_on_active"
    t.index ["gstin"], name: "index_customers_on_gstin"
    t.index ["metadata"], name: "index_customers_on_metadata", using: :gin
    t.index ["organisation_id", "name"], name: "index_customers_on_organisation_id_and_name"
    t.index ["organisation_id"], name: "index_customers_on_organisation_id"
    t.index ["phone"], name: "index_customers_on_phone"
  end

  create_table "digitise_imports", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "user_id", null: false
    t.bigint "purchase_invoice_id"
    t.string "status", default: "pending", null: false
    t.string "file_name"
    t.integer "file_size"
    t.string "file_content_type"
    t.text "file_data"
    t.text "raw_response"
    t.jsonb "parsed_data", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "attempt_count", default: 0, null: false
    t.jsonb "attempt_log", default: [], null: false
    t.string "ai_provider"
    t.index ["organisation_id"], name: "index_digitise_imports_on_organisation_id"
    t.index ["purchase_invoice_id"], name: "index_digitise_imports_on_purchase_invoice_id"
    t.index ["status"], name: "index_digitise_imports_on_status"
    t.index ["user_id"], name: "index_digitise_imports_on_user_id"
  end

  create_table "organisation_product_categories", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "product_category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organisation_id", "product_category_id"], name: "idx_org_product_categories_unique", unique: true
    t.index ["organisation_id"], name: "index_organisation_product_categories_on_organisation_id"
    t.index ["product_category_id"], name: "index_organisation_product_categories_on_product_category_id"
  end

  create_table "organisation_products", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "product_id"
    t.decimal "mrp", precision: 10, scale: 2
    t.boolean "active", default: true, null: false
    t.string "internal_code"
    t.text "local_description"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_organisation_products_on_active"
    t.index ["internal_code"], name: "index_organisation_products_on_internal_code"
    t.index ["organisation_id", "product_id"], name: "idx_org_products_unique", unique: true, where: "(product_id IS NOT NULL)"
    t.index ["organisation_id"], name: "index_organisation_products_on_organisation_id"
    t.index ["product_id"], name: "index_organisation_products_on_product_id"
  end

  create_table "organisations", force: :cascade do |t|
    t.string "name", null: false
    t.string "gst_number"
    t.text "address"
    t.string "subscription_plan", default: "basic"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gst_number"], name: "index_organisations_on_gst_number", unique: true
  end

  create_table "product_categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "import_key", default: "material_code"
    t.string "import_key_label", default: "Material Code"
    t.boolean "is_paint_type", default: false, null: false
    t.index ["active"], name: "index_product_categories_on_active"
    t.index ["name"], name: "index_product_categories_on_name", unique: true
  end

  create_table "product_imports", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "user_id", null: false
    t.string "file_name", null: false
    t.integer "file_size", default: 0
    t.string "status", default: "pending", null: false
    t.integer "total_rows", default: 0
    t.integer "success_count", default: 0
    t.integer "update_count", default: 0
    t.integer "error_count", default: 0
    t.jsonb "error_rows", default: []
    t.text "file_data"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_product_imports_on_created_at"
    t.index ["organisation_id"], name: "index_product_imports_on_organisation_id"
    t.index ["status"], name: "index_product_imports_on_status"
    t.index ["user_id"], name: "index_product_imports_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "product_category_id", null: false
    t.bigint "base_uom_id", null: false
    t.string "material_code"
    t.string "product_code"
    t.string "pack_code"
    t.text "description"
    t.string "hsn_code"
    t.decimal "gst_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "mrp", precision: 10, scale: 2
    t.jsonb "metadata", default: {}
    t.bigint "brand_id", null: false
    t.index ["active"], name: "index_products_on_active"
    t.index ["base_uom_id"], name: "index_products_on_base_uom_id"
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["hsn_code"], name: "index_products_on_hsn_code"
    t.index ["material_code"], name: "index_products_on_material_code", unique: true, where: "(material_code IS NOT NULL)"
    t.index ["metadata"], name: "index_products_on_metadata", using: :gin
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["product_code"], name: "index_products_on_product_code", unique: true, where: "(product_code IS NOT NULL)"
  end

  create_table "purchase_invoice_items", force: :cascade do |t|
    t.bigint "purchase_invoice_id", null: false
    t.bigint "product_id"
    t.boolean "unmatched", default: false, null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.decimal "unit_rate", precision: 10, scale: 2, null: false
    t.decimal "total_amount", precision: 12, scale: 2, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metadata"], name: "index_purchase_invoice_items_on_metadata", using: :gin
    t.index ["product_id"], name: "index_purchase_invoice_items_on_product_id"
    t.index ["purchase_invoice_id"], name: "index_purchase_invoice_items_on_purchase_invoice_id"
    t.index ["unmatched"], name: "index_purchase_invoice_items_on_unmatched"
  end

  create_table "purchase_invoices", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "supplier_id"
    t.bigint "user_id", null: false
    t.string "status", default: "draft", null: false
    t.string "invoice_number"
    t.date "invoice_date"
    t.date "delivery_date"
    t.decimal "total_taxable_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "total_tax_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0"
    t.datetime "confirmed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "payment_due_date"
    t.index ["invoice_date"], name: "index_purchase_invoices_on_invoice_date"
    t.index ["invoice_number"], name: "index_purchase_invoices_on_invoice_number"
    t.index ["metadata"], name: "index_purchase_invoices_on_metadata", using: :gin
    t.index ["organisation_id"], name: "index_purchase_invoices_on_organisation_id"
    t.index ["payment_due_date"], name: "index_purchase_invoices_on_payment_due_date"
    t.index ["status"], name: "index_purchase_invoices_on_status"
    t.index ["supplier_id"], name: "index_purchase_invoices_on_supplier_id"
    t.index ["user_id"], name: "index_purchase_invoices_on_user_id"
  end

  create_table "purchase_payments", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "purchase_invoice_id", null: false
    t.bigint "supplier_id"
    t.bigint "user_id", null: false
    t.date "payment_date", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "payment_mode", default: "bank_transfer", null: false
    t.string "reference_number"
    t.string "payment_number"
    t.text "notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metadata"], name: "index_purchase_payments_on_metadata", using: :gin
    t.index ["organisation_id"], name: "index_purchase_payments_on_organisation_id"
    t.index ["payment_date"], name: "index_purchase_payments_on_payment_date"
    t.index ["payment_mode"], name: "index_purchase_payments_on_payment_mode"
    t.index ["payment_number"], name: "index_purchase_payments_on_payment_number", unique: true, where: "(payment_number IS NOT NULL)"
    t.index ["purchase_invoice_id"], name: "index_purchase_payments_on_purchase_invoice_id"
    t.index ["supplier_id"], name: "index_purchase_payments_on_supplier_id"
    t.index ["user_id"], name: "index_purchase_payments_on_user_id"
  end

  create_table "sale_payments", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "sales_invoice_id", null: false
    t.bigint "customer_id"
    t.bigint "user_id", null: false
    t.date "payment_date", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "payment_mode", default: "cash", null: false
    t.string "reference_number"
    t.text "notes"
    t.string "receipt_number"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_sale_payments_on_customer_id"
    t.index ["metadata"], name: "index_sale_payments_on_metadata", using: :gin
    t.index ["organisation_id"], name: "index_sale_payments_on_organisation_id"
    t.index ["payment_date"], name: "index_sale_payments_on_payment_date"
    t.index ["payment_mode"], name: "index_sale_payments_on_payment_mode"
    t.index ["receipt_number"], name: "index_sale_payments_on_receipt_number", unique: true, where: "(receipt_number IS NOT NULL)"
    t.index ["sales_invoice_id"], name: "index_sale_payments_on_sales_invoice_id"
    t.index ["user_id"], name: "index_sale_payments_on_user_id"
  end

  create_table "sales_invoice_items", force: :cascade do |t|
    t.bigint "sales_invoice_id", null: false
    t.bigint "product_id"
    t.bigint "shade_catalogue_id"
    t.string "line_type", default: "product", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.decimal "unit_rate", precision: 10, scale: 4, default: "0.0", null: false
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "taxable_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "base_product_id"
    t.bigint "tinter_product_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.index ["base_product_id"], name: "index_sales_invoice_items_on_base_product_id"
    t.index ["line_type"], name: "index_sales_invoice_items_on_line_type"
    t.index ["metadata"], name: "index_sales_invoice_items_on_metadata", using: :gin
    t.index ["product_id"], name: "index_sales_invoice_items_on_product_id"
    t.index ["sales_invoice_id"], name: "index_sales_invoice_items_on_sales_invoice_id"
    t.index ["shade_catalogue_id"], name: "index_sales_invoice_items_on_shade_catalogue_id"
    t.index ["tinter_product_id"], name: "index_sales_invoice_items_on_tinter_product_id"
  end

  create_table "sales_invoices", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "customer_id"
    t.bigint "user_id", null: false
    t.string "status", default: "draft", null: false
    t.string "invoice_number"
    t.date "invoice_date"
    t.string "payment_mode"
    t.boolean "reverse_charge", default: false, null: false
    t.decimal "total_taxable_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "total_tax_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "total_discount_amount", precision: 12, scale: 2, default: "0.0"
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0"
    t.datetime "confirmed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "overall_discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.date "payment_due_date"
    t.datetime "voided_at"
    t.bigint "voided_by_id"
    t.index ["customer_id"], name: "index_sales_invoices_on_customer_id"
    t.index ["invoice_date"], name: "index_sales_invoices_on_invoice_date"
    t.index ["invoice_number"], name: "index_sales_invoices_on_invoice_number"
    t.index ["metadata"], name: "index_sales_invoices_on_metadata", using: :gin
    t.index ["organisation_id"], name: "index_sales_invoices_on_organisation_id"
    t.index ["payment_due_date"], name: "index_sales_invoices_on_payment_due_date"
    t.index ["payment_mode"], name: "index_sales_invoices_on_payment_mode"
    t.index ["status"], name: "index_sales_invoices_on_status"
    t.index ["user_id"], name: "index_sales_invoices_on_user_id"
    t.index ["voided_by_id"], name: "index_sales_invoices_on_voided_by_id"
  end

  create_table "shade_catalogue_imports", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "user_id", null: false
    t.bigint "product_category_id", null: false
    t.string "file_name", null: false
    t.integer "file_size", default: 0
    t.string "status", default: "pending", null: false
    t.integer "total_rows", default: 0
    t.integer "success_count", default: 0
    t.integer "update_count", default: 0
    t.integer "error_count", default: 0
    t.jsonb "error_rows", default: []
    t.text "file_data"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_shade_catalogue_imports_on_created_at"
    t.index ["organisation_id"], name: "index_shade_catalogue_imports_on_organisation_id"
    t.index ["product_category_id"], name: "index_shade_catalogue_imports_on_product_category_id"
    t.index ["status"], name: "index_shade_catalogue_imports_on_status"
    t.index ["user_id"], name: "index_shade_catalogue_imports_on_user_id"
  end

  create_table "shade_catalogues", force: :cascade do |t|
    t.bigint "product_category_id", null: false
    t.string "shade_code", null: false
    t.string "shade_name", null: false
    t.string "manufacturer"
    t.string "colour_family"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "brand_id"
    t.index ["active"], name: "index_shade_catalogues_on_active"
    t.index ["brand_id"], name: "index_shade_catalogues_on_brand_id"
    t.index ["colour_family"], name: "index_shade_catalogues_on_colour_family"
    t.index ["manufacturer"], name: "index_shade_catalogues_on_manufacturer"
    t.index ["product_category_id"], name: "index_shade_catalogues_on_product_category_id"
    t.index ["shade_code", "product_category_id"], name: "idx_shade_code_per_category", unique: true
    t.index ["shade_code"], name: "index_shade_catalogues_on_shade_code"
  end

  create_table "stock_ledgers", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "product_id", null: false
    t.bigint "user_id", null: false
    t.string "entry_type", null: false
    t.decimal "quantity", precision: 12, scale: 3, null: false
    t.decimal "unit_cost", precision: 10, scale: 2
    t.text "notes"
    t.string "reference_type"
    t.bigint "reference_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_stock_ledgers_on_created_at"
    t.index ["entry_type"], name: "index_stock_ledgers_on_entry_type"
    t.index ["organisation_id", "product_id"], name: "index_stock_ledgers_on_organisation_id_and_product_id"
    t.index ["organisation_id"], name: "index_stock_ledgers_on_organisation_id"
    t.index ["product_id"], name: "index_stock_ledgers_on_product_id"
    t.index ["reference_type", "reference_id"], name: "index_stock_ledgers_on_reference_type_and_reference_id"
    t.index ["user_id"], name: "index_stock_ledgers_on_user_id"
  end

  create_table "stock_levels", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "avg_cost", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organisation_id", "product_id"], name: "index_stock_levels_on_organisation_id_and_product_id", unique: true
    t.index ["organisation_id"], name: "index_stock_levels_on_organisation_id"
    t.index ["product_id"], name: "index_stock_levels_on_product_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "name", null: false
    t.string "gstin"
    t.string "pan"
    t.string "state"
    t.string "state_code"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "organisation_id", null: false
    t.index ["active"], name: "index_suppliers_on_active"
    t.index ["gstin"], name: "index_suppliers_on_gstin"
    t.index ["metadata"], name: "index_suppliers_on_metadata", using: :gin
    t.index ["organisation_id", "name"], name: "index_suppliers_on_organisation_id_and_name", unique: true
    t.index ["organisation_id"], name: "index_suppliers_on_organisation_id"
  end

  create_table "uoms", force: :cascade do |t|
    t.string "name", null: false
    t.string "short_name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_uoms_on_active"
    t.index ["name"], name: "index_uoms_on_name", unique: true
    t.index ["short_name"], name: "index_uoms_on_short_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "organisation_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "phone_number"
    t.jsonb "preferences", default: {}, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organisation_id"], name: "index_users_on_organisation_id"
    t.index ["preferences"], name: "index_users_on_preferences", using: :gin
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "customers", "organisations"
  add_foreign_key "organisation_product_categories", "organisations"
  add_foreign_key "organisation_product_categories", "product_categories"
  add_foreign_key "organisation_products", "organisations"
  add_foreign_key "organisation_products", "products"
  add_foreign_key "product_imports", "organisations"
  add_foreign_key "product_imports", "users"
  add_foreign_key "products", "brands"
  add_foreign_key "products", "product_categories"
  add_foreign_key "products", "uoms", column: "base_uom_id"
  add_foreign_key "purchase_invoice_items", "products"
  add_foreign_key "purchase_invoice_items", "purchase_invoices"
  add_foreign_key "purchase_invoices", "organisations"
  add_foreign_key "purchase_invoices", "suppliers"
  add_foreign_key "purchase_invoices", "users"
  add_foreign_key "purchase_payments", "organisations"
  add_foreign_key "purchase_payments", "purchase_invoices"
  add_foreign_key "purchase_payments", "suppliers"
  add_foreign_key "purchase_payments", "users"
  add_foreign_key "sale_payments", "customers"
  add_foreign_key "sale_payments", "organisations"
  add_foreign_key "sale_payments", "sales_invoices"
  add_foreign_key "sale_payments", "users"
  add_foreign_key "sales_invoice_items", "products"
  add_foreign_key "sales_invoice_items", "products", column: "base_product_id"
  add_foreign_key "sales_invoice_items", "products", column: "tinter_product_id"
  add_foreign_key "sales_invoice_items", "sales_invoices"
  add_foreign_key "sales_invoice_items", "shade_catalogues"
  add_foreign_key "sales_invoices", "customers"
  add_foreign_key "sales_invoices", "organisations"
  add_foreign_key "sales_invoices", "users"
  add_foreign_key "shade_catalogue_imports", "organisations"
  add_foreign_key "shade_catalogue_imports", "product_categories"
  add_foreign_key "shade_catalogue_imports", "users"
  add_foreign_key "shade_catalogues", "brands"
  add_foreign_key "shade_catalogues", "product_categories"
  add_foreign_key "stock_ledgers", "organisations"
  add_foreign_key "stock_ledgers", "products"
  add_foreign_key "stock_ledgers", "users"
  add_foreign_key "stock_levels", "organisations"
  add_foreign_key "stock_levels", "products"
  add_foreign_key "suppliers", "organisations"
end
