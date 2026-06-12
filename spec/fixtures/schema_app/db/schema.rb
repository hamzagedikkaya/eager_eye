# frozen_string_literal: true

ActiveRecord::Schema.define(version: 20_240_101_000_000) do
  create_table "eod_items", force: :cascade do |t|
    t.float "comsn_rate"
    t.integer "vat_rate"
    t.references "end_of_day_report"
    t.datetime "created_at", null: false
  end

  create_table "merchants", force: :cascade do |t|
    t.string "name"
    t.float "service_fee_rate"
  end
end
