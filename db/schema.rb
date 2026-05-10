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

ActiveRecord::Schema[7.1].define(version: 2026_05_10_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "brands", force: :cascade do |t|
    t.string "name", null: false
    t.string "short_name"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "aliases", default: [], array: true
    t.index ["active"], name: "index_brands_on_active"
    t.index ["aliases"], name: "idx_brands_aliases_gin", using: :gin
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
    t.string "session_id", comment: "UUID grouping multiple uploads of the same invoice"
    t.integer "page_count", comment: "Total pages the AI detected in the uploaded file"
    t.integer "pages_scanned", comment: "Number of pages actually sent to AI"
    t.text "preview_image", comment: "Base64 JPEG of page 1 for the review preview panel"
    t.index ["organisation_id"], name: "index_digitise_imports_on_organisation_id"
    t.index ["purchase_invoice_id"], name: "index_digitise_imports_on_purchase_invoice_id"
    t.index ["session_id"], name: "index_digitise_imports_on_session_id"
    t.index ["status"], name: "index_digitise_imports_on_status"
    t.index ["user_id"], name: "index_digitise_imports_on_user_id"
  end

  create_table "external_api_logs", force: :cascade do |t|
    t.string "service", null: false
    t.string "operation", null: false
    t.string "status", default: "pending", null: false
    t.integer "http_status"
    t.float "duration_ms"
    t.text "request_body"
    t.text "response_body"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.bigint "organisation_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_external_api_logs_on_created_at"
    t.index ["operation"], name: "index_external_api_logs_on_operation"
    t.index ["organisation_id"], name: "index_external_api_logs_on_organisation_id"
    t.index ["service"], name: "index_external_api_logs_on_service"
    t.index ["status"], name: "index_external_api_logs_on_status"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "gst_credit_ledger_entries", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.integer "period_year", null: false
    t.integer "period_month", null: false
    t.decimal "opening_igst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "opening_cgst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "opening_sgst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_igst_itc", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_cgst_itc", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_sgst_itc", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_igst_out", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_cgst_out", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "period_sgst_out", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "closing_igst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "closing_cgst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "closing_sgst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "cash_igst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "cash_cgst", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "cash_sgst", precision: 12, scale: 2, default: "0.0", null: false
    t.boolean "period_closed", default: false, null: false
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["closed_by_id"], name: "index_gst_credit_ledger_entries_on_closed_by_id"
    t.index ["organisation_id", "period_year", "period_month"], name: "idx_gst_credit_ledger_unique_period", unique: true
    t.index ["organisation_id"], name: "index_gst_credit_ledger_entries_on_organisation_id"
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
    t.string "state"
    t.string "state_code"
    t.string "gstin"
    t.string "pan"
    t.jsonb "settings", default: {}, null: false
    t.index ["gst_number"], name: "index_organisations_on_gst_number", unique: true
    t.index ["settings"], name: "idx_organisations_settings_gin", using: :gin
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

  create_table "product_merge_logs", force: :cascade do |t|
    t.bigint "merged_product_id", null: false
    t.bigint "target_product_id", null: false
    t.bigint "performed_by_id", null: false
    t.decimal "stock_transferred", precision: 12, scale: 4, default: "0.0"
    t.integer "pi_items_moved", default: 0, null: false
    t.integer "ledger_entries_moved", default: 0, null: false
    t.integer "stock_level_rows_merged", default: 0, null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "merged_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merged_at"], name: "idx_product_merge_logs_merged_at"
    t.index ["merged_product_id"], name: "idx_product_merge_logs_merged"
    t.index ["performed_by_id"], name: "idx_product_merge_logs_performed_by"
    t.index ["target_product_id"], name: "idx_product_merge_logs_target"
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
    t.bigint "brand_id"
    t.boolean "under_review", default: false, null: false
    t.string "catalogue_status", default: "active", null: false
    t.string "source", default: "manual"
    t.jsonb "internet_details", default: {}
    t.datetime "internet_details_fetched_at"
    t.bigint "merged_into_product_id"
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.index ["active"], name: "index_products_on_active"
    t.index ["base_uom_id"], name: "index_products_on_base_uom_id"
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["catalogue_status"], name: "idx_products_catalogue_status"
    t.index ["description"], name: "idx_products_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["hsn_code"], name: "index_products_on_hsn_code"
    t.index ["internet_details"], name: "idx_products_internet_details_gin", using: :gin
    t.index ["material_code"], name: "idx_products_material_code_trgm", opclass: :gin_trgm_ops, where: "(material_code IS NOT NULL)", using: :gin
    t.index ["material_code"], name: "idx_products_material_code_unique_confirmed", unique: true, where: "((material_code IS NOT NULL) AND (under_review = false))"
    t.index ["merged_into_product_id"], name: "idx_products_merged_into_product_id"
    t.index ["metadata"], name: "index_products_on_metadata", using: :gin
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["product_code"], name: "index_products_on_product_code", unique: true, where: "(product_code IS NOT NULL)"
    t.index ["source"], name: "idx_products_source"
    t.index ["under_review"], name: "idx_products_under_review", where: "(under_review = true)"
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
    t.decimal "gst_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "taxable_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "supply_type", default: "intra_state", null: false
    t.decimal "cgst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "sgst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "igst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["gst_rate"], name: "index_purchase_invoice_items_on_gst_rate"
    t.index ["metadata"], name: "index_purchase_invoice_items_on_metadata", using: :gin
    t.index ["product_id"], name: "index_purchase_invoice_items_on_product_id"
    t.index ["purchase_invoice_id"], name: "index_purchase_invoice_items_on_purchase_invoice_id"
    t.index ["supply_type"], name: "index_purchase_invoice_items_on_supply_type"
    t.index ["taxable_amount"], name: "index_purchase_invoice_items_on_taxable_amount"
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
    t.index ["metadata"], name: "index_purchase_invoices_on_metadata", using: :gin
    t.index ["organisation_id", "invoice_number"], name: "idx_purchase_invoices_org_invoice_number_unique", unique: true, where: "((invoice_number IS NOT NULL) AND ((invoice_number)::text <> ''::text))"
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

  create_table "referrers", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "trade", default: "painter", null: false
    t.string "address"
    t.string "area"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organisation_id", "active"], name: "index_referrers_on_organisation_id_and_active"
    t.index ["organisation_id", "phone"], name: "idx_referrers_org_phone_unique", unique: true, where: "(phone IS NOT NULL)"
    t.index ["organisation_id", "trade"], name: "index_referrers_on_organisation_id_and_trade"
    t.index ["organisation_id"], name: "index_referrers_on_organisation_id"
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
    t.string "supply_type", default: "intra_state", null: false
    t.decimal "gst_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "cgst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "sgst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "igst_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["base_product_id"], name: "index_sales_invoice_items_on_base_product_id"
    t.index ["gst_rate"], name: "index_sales_invoice_items_on_gst_rate"
    t.index ["line_type"], name: "index_sales_invoice_items_on_line_type"
    t.index ["metadata"], name: "index_sales_invoice_items_on_metadata", using: :gin
    t.index ["product_id"], name: "index_sales_invoice_items_on_product_id"
    t.index ["sales_invoice_id"], name: "index_sales_invoice_items_on_sales_invoice_id"
    t.index ["shade_catalogue_id"], name: "index_sales_invoice_items_on_shade_catalogue_id"
    t.index ["supply_type"], name: "index_sales_invoice_items_on_supply_type"
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
    t.decimal "overall_discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0"
    t.datetime "confirmed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "payment_due_date"
    t.datetime "voided_at"
    t.bigint "voided_by_id"
    t.bigint "referrer_id"
    t.index ["customer_id"], name: "index_sales_invoices_on_customer_id"
    t.index ["invoice_date"], name: "index_sales_invoices_on_invoice_date"
    t.index ["invoice_number"], name: "index_sales_invoices_on_invoice_number"
    t.index ["metadata"], name: "index_sales_invoices_on_metadata", using: :gin
    t.index ["organisation_id"], name: "index_sales_invoices_on_organisation_id"
    t.index ["payment_due_date"], name: "index_sales_invoices_on_payment_due_date"
    t.index ["payment_mode"], name: "index_sales_invoices_on_payment_mode"
    t.index ["referrer_id"], name: "index_sales_invoices_on_referrer_id"
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
    t.bigint "organisation_id", null: false
    t.string "name", null: false
    t.string "gstin"
    t.string "pan"
    t.string "state"
    t.string "state_code"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_suppliers_on_active"
    t.index ["gstin"], name: "index_suppliers_on_gstin"
    t.index ["metadata"], name: "index_suppliers_on_metadata", using: :gin
    t.index ["organisation_id", "name"], name: "index_suppliers_on_organisation_id_and_name", unique: true
    t.index ["organisation_id"], name: "index_suppliers_on_organisation_id"
  end

  create_table "tinting_machine_canisters", force: :cascade do |t|
    t.bigint "organisation_id", null: false
    t.bigint "brand_id", null: false
    t.bigint "product_id"
    t.bigint "loaded_by_id"
    t.integer "slot_number", null: false
    t.integer "initial_volume_ml", null: false
    t.string "status", default: "empty", null: false
    t.decimal "dispensed_volume_ml", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "loaded_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["brand_id"], name: "index_tinting_machine_canisters_on_brand_id"
    t.index ["loaded_by_id"], name: "index_tinting_machine_canisters_on_loaded_by_id"
    t.index ["metadata"], name: "index_tinting_machine_canisters_on_metadata", using: :gin
    t.index ["organisation_id", "brand_id", "slot_number"], name: "idx_tinting_canisters_org_brand_slot", unique: true
    t.index ["organisation_id"], name: "index_tinting_machine_canisters_on_organisation_id"
    t.index ["product_id"], name: "index_tinting_machine_canisters_on_product_id"
  end

  create_table "tinting_machine_logs", force: :cascade do |t|
    t.bigint "tinting_machine_canister_id", null: false
    t.bigint "organisation_id", null: false
    t.bigint "user_id"
    t.string "action", null: false
    t.decimal "volume_ml", precision: 10, scale: 2, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organisation_id"], name: "index_tinting_machine_logs_on_organisation_id"
    t.index ["tinting_machine_canister_id"], name: "index_tinting_machine_logs_on_tinting_machine_canister_id"
    t.index ["user_id"], name: "index_tinting_machine_logs_on_user_id"
  end

  create_table "uoms", force: :cascade do |t|
    t.string "name", null: false
    t.string "short_name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "aliases", default: [], array: true
    t.index ["active"], name: "index_uoms_on_active"
    t.index ["aliases"], name: "idx_uoms_aliases_gin", using: :gin
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
  add_foreign_key "gst_credit_ledger_entries", "organisations"
  add_foreign_key "gst_credit_ledger_entries", "users", column: "closed_by_id"
  add_foreign_key "organisation_product_categories", "organisations"
  add_foreign_key "organisation_product_categories", "product_categories"
  add_foreign_key "organisation_products", "organisations"
  add_foreign_key "organisation_products", "products"
  add_foreign_key "product_imports", "organisations"
  add_foreign_key "product_imports", "users"
  add_foreign_key "products", "brands"
  add_foreign_key "products", "product_categories"
  add_foreign_key "products", "products", column: "merged_into_product_id"
  add_foreign_key "products", "uoms", column: "base_uom_id"
  add_foreign_key "products", "users", column: "reviewed_by_id"
  add_foreign_key "purchase_invoice_items", "products"
  add_foreign_key "purchase_invoice_items", "purchase_invoices"
  add_foreign_key "purchase_invoices", "organisations"
  add_foreign_key "purchase_invoices", "suppliers"
  add_foreign_key "purchase_invoices", "users"
  add_foreign_key "purchase_payments", "organisations"
  add_foreign_key "purchase_payments", "purchase_invoices"
  add_foreign_key "purchase_payments", "suppliers"
  add_foreign_key "purchase_payments", "users"
  add_foreign_key "referrers", "organisations"
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
  add_foreign_key "sales_invoices", "referrers"
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
  add_foreign_key "tinting_machine_canisters", "brands"
  add_foreign_key "tinting_machine_canisters", "organisations"
  add_foreign_key "tinting_machine_canisters", "products"
  add_foreign_key "tinting_machine_canisters", "users", column: "loaded_by_id"
  add_foreign_key "tinting_machine_logs", "organisations"
  add_foreign_key "tinting_machine_logs", "tinting_machine_canisters"
  add_foreign_key "tinting_machine_logs", "users"
end
