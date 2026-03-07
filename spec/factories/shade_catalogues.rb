# spec/factories/shade_catalogues.rb
FactoryBot.define do
  factory :shade_catalogue do
    association :product_category, :paint_type
    brand
    sequence(:shade_code) { |n| "SHD#{n.to_s.rjust(4, '0')}" }
    sequence(:shade_name) { |n| "Shade Colour #{n}" }
    colour_family { "Red" }
    active { true }
  end
end
