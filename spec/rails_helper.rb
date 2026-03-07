# spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'capybara/rspec'

# Load support files
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot short syntax
  config.include FactoryBot::Syntax::Methods

  # Devise helpers for feature specs
  config.include Devise::Test::IntegrationHelpers, type: :feature
  config.include Warden::Test::Helpers, type: :feature

  config.after(:each, type: :feature) { Warden.test_reset! }
end


# ------------------------------
# Capybara + Selenium Drivers
# ------------------------------

# Headless Chrome (default - used in CI)
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,1400')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Visible Chrome (used for debugging)
Capybara.register_driver :selenium_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--window-size=1400,1400')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end


# ------------------------------
# Capybara configuration
# ------------------------------

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_chrome_headless


# Switch driver depending on environment
RSpec.configure do |config|
  config.before(:each, type: :feature) do
    if ENV['HEADLESS'] == 'false'
      Capybara.current_driver = :selenium_chrome
    else
      Capybara.current_driver = :selenium_chrome_headless
    end
  end
end