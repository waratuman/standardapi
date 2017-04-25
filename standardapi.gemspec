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

  spec.files         = `git ls-files -- README.md {lib,ext}/*`.split("\n")
  spec.test_files    = `git ls-files -- {test}/*`.split("\n")
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'rails', '~> 5.0', '>= 5.0.0'
  spec.add_runtime_dependency 'activesupport', '~> 5.0', '>= 5.0.0'
  spec.add_runtime_dependency 'actionpack', '~> 5.0', '>= 5.0.0'
  spec.add_runtime_dependency 'activerecord-sort', '~> 5.0', '>= 5.0.0'
  spec.add_runtime_dependency 'activerecord-filter', '~> 5.0', '>= 5.0.0'
  spec.add_runtime_dependency 'jbuilder', '~> 2.6', '>= 2.6.0'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "factory_girl_rails"
  spec.add_development_dependency "faker"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency 'mocha'
  spec.add_development_dependency 'rails-controller-testing'

  # spec.add_development_dependency 'activerecord'
  # spec.add_development_dependency 'sdoc',                '~> 0.4'
  # spec.add_development_dependency 'sdoc-templates-42floors', '~> 0.3'

end
