# spec/factories/gst_factories.rb
#
# GST-specific factory definitions.
#
# DESIGN DECISION: We do NOT use FactoryBot.modify for :organisation because
# load order is alphabetical (gst_ before organisations_), so :organisation
# is not yet registered when this file runs.
#
# Instead, specs pass state/state_code inline:
#   create(:organisation, state: 'West Bengal', state_code: '19')
#
# If :supplier, :customer, or :product already exist in your project's
# factories, rename them to :gst_supplier / :gst_customer / :gst_product
# and update the spec files accordingly.

FactoryBot.define do

  # ── GST User ──────────────────────────────────────────────────────────────
  # Named :gst_user to avoid conflict with existing :user factory.
  factory :gst_user, class: 'User' do
    association :organisation
    sequence(:email) { |n| "gst_user#{n}@example.com" }
    first_name       { 'GST' }
    last_name        { 'User' }
    role             { :admin }
    password         { 'password123' }
    password_confirmation { 'password123' }
    status           { :active }
  end

  # ── Supplier ─────────────────────────────────────────────────────────────
  factory :gst_supplier, class: 'Supplier' do
    association :organisation
    sequence(:name) { |n| "Supplier #{n}" }
    state      { 'West Bengal' }
    state_code { '19' }
    gstin      { nil }

    trait :intra_state do
      state      { 'West Bengal' }
      state_code { '19' }
    end

    trait :inter_state do
      state      { 'Maharashtra' }
      state_code { '27' }
      sequence(:name) { |n| "Mumbai Supplier #{n}" }
    end

    trait :no_state do
      state      { nil }
      state_code { nil }
    end
  end

  # ── Customer ─────────────────────────────────────────────────────────────
  factory :gst_customer, class: 'Customer' do
    association :organisation
    sequence(:name) { |n| "Customer #{n}" }
    state      { 'West Bengal' }
    state_code { '19' }
    gstin      { nil }

    trait :intra_state do
      state      { 'West Bengal' }
      state_code { '19' }
    end

    trait :inter_state do
      state      { 'Bihar' }
      state_code { '10' }
      sequence(:name) { |n| "Bihar Customer #{n}" }
    end

    trait :b2b do
      sequence(:gstin) { |n| "10BBBBB#{n.to_s.rjust(4, '0')}B1Z5" }
    end

    trait :no_state do
      state      { nil }
      state_code { nil }
    end
  end

  # ── Product ──────────────────────────────────────────────────────────────
  factory :gst_product, class: 'Product' do
    association :product_category
    association :base_uom, factory: :uom
    brand
    sequence(:description)   { |n| "Product #{n}" }
    sequence(:material_code) { |n| "GMAT#{n.to_s.rjust(4, '0')}" }
    gst_rate { 18.0 }
    hsn_code { '32081090' }
    active   { true }

    trait :gst_12 do
      gst_rate { 12.0 }
      hsn_code { '73269099' }
    end

    trait :gst_18 do
      gst_rate { 18.0 }
      hsn_code { '32081090' }
    end

    trait :gst_28 do
      gst_rate { 28.0 }
      hsn_code { '25010010' }
    end

    trait :gst_zero do
      gst_rate { 0.0 }
      hsn_code { '22011010' }
    end

    trait :no_hsn do
      hsn_code { nil }
    end
  end

  # ── Purchase Invoice ──────────────────────────────────────────────────────
  factory :purchase_invoice do
    association :organisation
    association :supplier, factory: :gst_supplier
    association :user, factory: :gst_user
    invoice_date         { Date.today }
    delivery_date        { Date.today + 7 }
    status               { 'draft' }
    total_amount         { 0 }
    total_taxable_amount { 0 }
    total_tax_amount     { 0 }

    trait :confirmed do
      status       { 'confirmed' }
      confirmed_at { Time.current }
    end
  end

  # ── Purchase Invoice Item ─────────────────────────────────────────────────
  factory :purchase_invoice_item do
    association :purchase_invoice
    association :product, factory: :gst_product
    quantity         { 10 }
    unit_rate        { 100.0 }
    total_amount     { 1180.0 }
    gst_rate         { 0 }
    taxable_amount   { 0 }
    tax_amount       { 0 }
    discount_percent { 0 }
    discount_amount  { 0 }
    supply_type      { 'intra_state' }
    cgst_amount      { 0 }
    sgst_amount      { 0 }
    igst_amount      { 0 }
    metadata         { {} }
    unmatched        { false }
  end

  # ── Sales Invoice ─────────────────────────────────────────────────────────
  factory :sales_invoice do
    association :organisation
    association :customer, factory: :gst_customer
    association :user, factory: :gst_user
    invoice_date         { Date.today }
    status               { 'draft' }
    total_amount         { 0 }
    total_taxable_amount { 0 }
    total_tax_amount     { 0 }

    trait :confirmed do
      status       { 'confirmed' }
      confirmed_at { Time.current }
    end

    trait :walk_in do
      customer { nil }
    end
  end

  # ── Sales Invoice Item ────────────────────────────────────────────────────
  factory :sales_invoice_item do
    association :sales_invoice
    association :product, factory: :gst_product
    line_type        { 'product' }
    quantity         { 5 }
    unit_rate        { 0 }
    total_amount     { 590.0 }
    taxable_amount   { 0 }
    tax_amount       { 0 }
    discount_percent { 0 }
    gst_rate         { 0 }
    supply_type      { 'intra_state' }
    cgst_amount      { 0 }
    sgst_amount      { 0 }
    igst_amount      { 0 }
    metadata         { { 'cgst_percent' => 9.0, 'sgst_percent' => 9.0 } }
  end

end