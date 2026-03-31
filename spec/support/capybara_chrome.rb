# spec/support/capybara_chrome.rb
#
# Configures Capybara to drive Google Chrome via Selenium WebDriver.
# Supports both headed (visible browser) and headless modes.
#
# DEPENDENCIES — add to Gemfile:
#   group :test do
#     gem 'capybara'
#     gem 'selenium-webdriver'
#     gem 'webdrivers'          # auto-downloads chromedriver
#     gem 'database_cleaner-active_record'
#   end
#
# ENVIRONMENT VARIABLES:
#   HEADED=true       → run with visible Chrome window (default: headless)
#   SLOW_MO=500       → add 500ms delay between actions (debugging)
#   BROWSER_WIDTH=1400 → window width (default 1400)
#   BROWSER_HEIGHT=900 → window height (default 900)

require 'capybara/rails'
require 'capybara/rspec'
require 'selenium-webdriver'

# ── Chrome driver registration ─────────────────────────────────────────────
Capybara.register_driver :chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  unless ENV['HEADED'] == 'true'
    options.add_argument('--headless=new')  # modern headless flag (Chrome 112+)
  end

  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-popup-blocking')
  options.add_argument('--disable-notifications')
  options.add_argument('--disable-infobars')
  options.add_argument('--disable-extensions')
  options.add_argument('--window-size=1400,900')

  # Suppress Chrome's "DevTools listening" console noise
  options.add_argument('--log-level=3')
  options.add_argument('--silent')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# ── Default driver & app host ─────────────────────────────────────────────
Capybara.default_driver    = :rack_test       # fast driver for non-JS specs
Capybara.javascript_driver = :chrome          # Chrome for :js => true specs
Capybara.default_max_wait_time = 10           # seconds to wait for elements
Capybara.server = :puma, { Silent: true }

# ── DatabaseCleaner: use transactions for non-JS, truncation for JS ────────
RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    # Selenium runs in a separate thread; must use truncation or deletion
    DatabaseCleaner.strategy = :truncation, {
      except: %w[ar_internal_metadata schema_migrations]
    }
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
