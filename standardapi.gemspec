require File.expand_path("../lib/standard_api/version", __FILE__)

Gem::Specification.new do |spec|
  spec.name          = "standardapi"
  spec.version       = StandardAPI::VERSION
  spec.licenses      = ['MIT']
  spec.authors       = ["James Bracy"]
  spec.email         = ["waratuman@gmail.com"]
  spec.homepage      = "https://github.com/waratuman/standardapi"
  spec.description   = %q{StandardAPI makes it easy to expose a query interface for your Rails models}
  spec.summary       = %q{StandardAPI makes it easy to expose a query interface for your Rails models}

  spec.extra_rdoc_files = %w(README.md)
  spec.rdoc_options.concat ['--main', 'README.md']

  spec.files         = `git ls-files -- README.md {lib,ext}/* test/standard_api/*`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
  spec.require_paths = ["lib", "test"]

  spec.add_runtime_dependency 'rails', '>= 7.2.2'
  spec.add_runtime_dependency 'activesupport', '>= 7.2.2'
  spec.add_runtime_dependency 'actionpack', '>= 7.2.2'
  spec.add_runtime_dependency 'activerecord-sort', '>= 6.1.0'
  spec.add_runtime_dependency 'activerecord-filter', '>= 8.1.0'

  spec.add_development_dependency 'pg'
  spec.add_development_dependency "bundler"
  spec.add_development_dependency 'oj'
  spec.add_development_dependency 'turbostreamer', '>= 1.11.0'
  spec.add_development_dependency 'jbuilder'
  spec.add_development_dependency "rake"
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "factory_bot_rails"
  spec.add_development_dependency "faker"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency 'mocha'
  spec.add_development_dependency 'benchmark-ips'
  # spec.add_development_dependency 'turbostreamer'
  # spec.add_development_dependency 'wankel'
  # spec.add_development_dependency 'ruby-prof'

end
