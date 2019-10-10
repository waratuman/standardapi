require "test_helper"
require "benchmark/ips"

TIME    = (ENV["BENCHMARK_TIME"] || 20).to_i
RECORDS = (ENV["BENCHMARK_RECORDS"] || TIME * 1000).to_i

app = ::ActionDispatch::IntegrationTest.new(:app)
properties = Array.new(1000) do
  photos = Array.new(10) { FactoryBot.create(:photo) }
  FactoryBot.create(:property, photos: photos)
end

Benchmark.ips(TIME) do |x|

  # ActionView::Template.unregister_template_handler :streamer
  # ActionView::Template.register_template_handler :jbuilder, JbuilderHandler

  x.report("#index.json.jbuilder") do
    app.get('/properties.json', params: { limit: 100 })
  end

  x.report("#show.json.jbuilder") do
    app.get("/properties/#{properties.sample.id}.json")
  end

  x.report("#show.json.jbuilder w/ include=photos") do
    app.get("/properties/#{properties.sample.id}.json", params: { include: :photos })
  end

  # ActionView::Template.unregister_template_handler :jbuilder
  # ActionView::Template.register_template_handler :streamer, TurboStreamer::Handler

  # x.report("#index.json.streamer") do
  #   app.get('/properties.json', params: { limit: 100 })
  # end

  # x.compare!

end
