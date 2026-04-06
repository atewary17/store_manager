require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StoreManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Load local environment variables
    # config/local_env.yml is gitignored — safe for API keys
    local_env_path = File.join(File.dirname(__FILE__), 'local_env.yml')
    if File.exist?(local_env_path)
      require 'yaml'
      YAML.load_file(local_env_path).each do |key, value|
        ENV[key.to_s] ||= value.to_s
      end
    end

    # ─────────────────────────────────────────────────────────
    # Then your existing module StoreManager / class Application continues
  end
end
