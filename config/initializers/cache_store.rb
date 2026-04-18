# config/initializers/cache_store.rb
#
# Cache store configuration.
# - Production with REDIS_URL set → Redis (high performance, shared across dynos)
# - Production without REDIS_URL  → Memory store (single process, fine for now)
# - Development/test              → Null store (no caching)
#
# To enable Redis on Render:
#   1. Add a Redis instance in Render dashboard
#   2. Set REDIS_URL environment variable
#   3. Deploy — caching switches automatically
#
if Rails.env.production?
  # Redis disabled until provisioned — using in-process memory store
  # To enable Redis later:
  #   1. Provision a Redis add-on and set REDIS_URL
  #   2. Uncomment the block below and remove the memory_store line
  #
  # if ENV['REDIS_URL'].present?
  #   Rails.application.config.cache_store = :redis_cache_store, {
  #     url:              ENV['REDIS_URL'],
  #     expires_in:       1.hour,
  #     namespace:        'storeerp',
  #     error_handler:    ->(method:, returning:, exception:) {
  #       Rails.logger.error "Redis cache error (#{method}): #{exception.message}"
  #     }
  #   }
  #   Rails.logger.info '[Cache] Using Redis cache store'
  # else
  Rails.application.config.cache_store = :memory_store, { size: 32.megabytes }
  Rails.logger.info '[Cache] Using memory store (Redis not configured)'
  # end
else
  Rails.application.config.cache_store = :null_store
end