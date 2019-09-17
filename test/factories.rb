FactoryBot.define do
  factory :account do
    name            { Faker::Name.name }

    trait(:nested)  { }
    trait(:invalid) do
      name { nil }
    end
  end
  
  factory :landlord do
    name            { Faker::Name.name }
  end

  factory :photo do
    format          { ['jpg', 'png', 'tiff'].sample }
  end

  factory :document do
    file            { fixture_file_upload(Rails.root + '../fixtures/photo.png', 'image/png') }
  end

  factory :pdf do
    type            { 'Pdf' }
    file            { fixture_file_upload(Rails.root + '../fixtures/photo.png', 'image/png') }
  end

  factory :reference do
    subject_type  { 'Photo' }
    subject_id    { create(:photo).id }
  end

  factory :property do
    name            { Faker::Lorem.words(number: Kernel.rand(1..4)).join(' ') }
    description     { Faker::Lorem.paragraphs.join("\n\n") }
    constructed     { Kernel.rand(1800..(Time.now.year - 2)) }
    size            { Kernel.rand(1000..10000000).to_f / 100 }
    active          { [true, false].sample }
    photos          { [create(:photo)] }

    trait(:nested)  do
      photos_attributes { [attributes_for(:photo)] }
    end

    trait(:invalid) do
      name { nil }
    end
  end

end