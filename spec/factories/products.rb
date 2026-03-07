# spec/factories/products.rb
FactoryBot.define do
  factory :product do
    product_category
    association :base_uom, factory: :uom
    brand
    sequence(:description) { |n| "Test Product #{n}" }
    sequence(:material_code) { |n| "MAT#{n.to_s.rjust(5, '0')}" }
    gst_rate { 18.0 }
    active { true }
  end
end
