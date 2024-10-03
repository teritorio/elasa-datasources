# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '>= 3'

gem 'activesupport'
gem 'bzip2-ffi'
gem 'http'
gem 'json'
gem 'jsonpath'
gem 'json-schema'
gem 'kiba'
gem 'logging'
gem 'nokogiri'
gem 'overpass_parser', git: 'https://github.com/teritorio/overpass_parser-rb.git'
gem 'rgeo'
gem 'rgeo-geojson'
gem 'sentry-ruby'
gem 'sorbet-runtime'
gem 'yaml'

group :development do
  gem 'rake'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rake', require: false
  gem 'sorbet'
  gem 'sorbet-rails'
  gem 'tapioca', require: false
  gem 'test-unit'

  # Only for sorbet typechecker
  gem 'psych'
  gem 'racc'
  gem 'rbi'
  gem 'yard'
end
