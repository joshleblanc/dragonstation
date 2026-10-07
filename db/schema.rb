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

ActiveRecord::Schema[8.1].define(version: 2026_10_07_140000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "digest", null: false
    t.string "prefix", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["digest"], name: "index_api_keys_on_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "cartridge_files", force: :cascade do |t|
    t.integer "cartridge_id", null: false
    t.string "path", null: false
    t.bigint "byte_size", null: false
    t.bigint "filetime", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cartridge_id", "path"], name: "index_cartridge_files_on_cartridge_id_and_path", unique: true
    t.index ["cartridge_id"], name: "index_cartridge_files_on_cartridge_id"
  end

  create_table "cartridges", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "console_version_id", null: false
    t.string "title", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "cart_name", null: false
    t.string "entry_path", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["console_version_id", "cart_name"], name: "index_cartridges_on_console_version_id_and_cart_name"
    t.index ["console_version_id"], name: "index_cartridges_on_console_version_id"
    t.index ["slug"], name: "index_cartridges_on_slug", unique: true
    t.index ["user_id"], name: "index_cartridges_on_user_id"
  end

  create_table "console_library_files", force: :cascade do |t|
    t.integer "console_version_id", null: false
    t.string "path", null: false
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["console_version_id", "path"], name: "index_console_library_files_on_console_version_id_and_path", unique: true
    t.index ["console_version_id"], name: "index_console_library_files_on_console_version_id"
  end

  create_table "console_versions", force: :cascade do |t|
    t.string "version", null: false
    t.string "title"
    t.text "notes"
    t.boolean "default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["default"], name: "index_console_versions_on_default"
    t.index ["version"], name: "index_console_versions_on_version", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.boolean "admin", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_keys", "users"
  add_foreign_key "cartridge_files", "cartridges"
  add_foreign_key "cartridges", "console_versions"
  add_foreign_key "cartridges", "users"
  add_foreign_key "console_library_files", "console_versions"
  add_foreign_key "sessions", "users"
end
