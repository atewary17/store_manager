source "https://rubygems.org"

ruby "3.3.5"

gem "rails", "~> 7.1.3", ">= 7.1.3.4"
gem "sprockets-rails"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
# gem "jsbundling-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

gem 'devise'
gem 'rack-cors'
gem 'paper_trail'
gem 'ostruct'
gem "groupdate"
gem 'matrix'
gem 'prawn'
gem 'prawn-table'
gem 'pundit'
gem 'cancancan'
gem 'good_job'
gem 'roo'           # Excel parsing
gem 'caxlsx'        # Excel generation (error reports)
gem 'caxlsx_rails'  # Rails integration
gem 'redis', '~> 5.0'          # later use
gem 'hiredis-client'           # faster Redis driver
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'
gem 'dotenv-rails'  # not grouped, so it loads in production too

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem 'letter_opener'
  gem 'minitest', '~> 5.0'
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  # gem 'dotenv-rails'
end

group :development do
  gem "web-console"
  gem 'pry-byebug'
end

group :test do
  gem 'selenium-webdriver'
  gem 'capybara'
  gem 'rspec_junit_formatter'
end

gem "importmap-rails", "~> 2.2"