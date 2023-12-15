FactoryBot.define do

  factory :account do
    name            { Faker::Name.name }

    trait(:nested)  { }
    trait(:invalid) do
      name { nil }
    end
  end

  factory :order do
    account
    name            { Faker::Name.name }
    price           { rand(100..1000) }
  end

end
