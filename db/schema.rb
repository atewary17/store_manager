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

ActiveRecord::Schema[7.1].define(version: 2026_02_25_184246) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["active"], name: "index_product_categories_on_active"
    t.index ["name"], name: "index_product_categories_on_name", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.bigint "product_category_id", null: false
    t.bigint "base_uom_id", null: false
    t.string "brand", null: false
    t.string "material_code"
    t.string "product_code"
    t.string "pack_code"
    t.text "description"
    t.string "hsn_code"
    t.decimal "gst_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_products_on_active"
    t.index ["base_uom_id"], name: "index_products_on_base_uom_id"
    t.index ["brand"], name: "index_products_on_brand"
    t.index ["hsn_code"], name: "index_products_on_hsn_code"
    t.index ["material_code"], name: "index_products_on_material_code", unique: true, where: "(material_code IS NOT NULL)"
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["product_code"], name: "index_products_on_product_code", unique: true, where: "(product_code IS NOT NULL)"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organisation_id"], name: "index_users_on_organisation_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "products", "product_categories"
  add_foreign_key "products", "uoms", column: "base_uom_id"
end
