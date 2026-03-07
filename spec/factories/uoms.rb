# spec/factories/uoms.rb
FactoryBot.define do
  factory :uom do
    sequence(:name) { |n| "Unit #{n}" }
    sequence(:short_name) { |n| "U#{n}" }
    active { true }
  end
end
