require File.expand_path("../lib/standard_api/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "standard-api"
  spec.version       = ActionController::StandardAPI::VERSION
  spec.licenses      = ['MIT']
  spec.authors       = ["Jon Bracy"]
  spec.email         = ["jonbracy@gmail.com"]
  spec.homepage      = "https://github.com/malomalo/standardapi"
  spec.description   = %q{StandardAPI makes it easy to expose a query interface for your Rails models}
  spec.summary       = %q{StandardAPI makes it easy to expose a query interface for your Rails models}

  spec.extra_rdoc_files = %w(README.md)
  spec.rdoc_options.concat ['--main', 'README.md']

  spec.files         = `git ls-files -- README.md {lib,ext}/*`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'activerecord-sort'
  spec.add_runtime_dependency 'activerecord-filter'
  spec.add_runtime_dependency 'actionpack', '~> 4.0'
    
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "factory_girl_rails"
  spec.add_development_dependency "faker"
  # spec.add_development_dependency 'sdoc',                '~> 0.4'
  # spec.add_development_dependency 'sdoc-templates-42floors', '~> 0.3'
end
