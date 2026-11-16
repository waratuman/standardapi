source "https://rubygems.org"

# Specify your gem's dependencies in sunstone.gemspec
gemspec

# Pin minitest to 5.x until Rails is compatible with minitest 6.0's API changes
gem 'minitest', '~> 5.0'

# TODO: Remove once json_schemer releases a fix. json_schemer 2.5.0 calls
# Regexp::Syntax#implements, which regexp_parser 2.13.2 removed, so it fails
# to load.
gem 'regexp_parser', '< 2.13.2'
