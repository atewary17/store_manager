# spec/factories/brands.rb
FactoryBot.define do
  factory :brand do
    sequence(:name) { |n| "Brand #{n}" }
    short_name { "BR" }
    active { true }
  end
end
