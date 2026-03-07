# spec/factories/product_categories.rb
FactoryBot.define do
  factory :product_category do
    sequence(:name) { |n| "Category #{n}" }
    description { "Test category" }
    active { true }
    is_paint_type { false }

    trait :paint_type do
      is_paint_type { true }
    end
  end
end
