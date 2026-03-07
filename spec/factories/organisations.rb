# spec/factories/organisations.rb
FactoryBot.define do
  factory :organisation do
    name { "Acme Paints" }
    gst_number { "27AABCU9999F1ZP" }
    address { "123 Main St" }
    subscription_plan { "pro" }
    status { 0 }
  end
end
