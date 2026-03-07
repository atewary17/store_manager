# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    organisation
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    first_name { "Test" }
    last_name { "User" }
    role { :staff }
    status { 0 }

    trait :super_admin do
      role { :super_admin }
      first_name { "Super" }
      last_name { "Admin" }
    end
  end
end
