# spec/service_helper.rb
#
# Minimal harness for plain service-object specs.
#
# spec/rails_helper.rb pulls in capybara and the browser support files, which
# feature specs need but service specs do not. Using it here would couple unit
# tests to a browser stack — and capybara is currently absent from the Gemfile,
# so requiring it aborts the run.
#
# Loads Rails (services need ActiveSupport, Rails.root, and autoloading) and
# nothing else. No database access — these specs are pure Ruby.
require 'spec_helper'

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'

RSpec.configure do |config|
  config.use_transactional_fixtures = false
end
