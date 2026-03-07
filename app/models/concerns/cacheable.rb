# app/models/concerns/cacheable.rb
#
# Include in any model to get cached counts and lookups.
# Cache is automatically invalidated after_commit (create/update/destroy).
#
# Usage:
#   class ProductCategory < ApplicationRecord
#     include Cacheable
#   end
#
#   ProductCategory.cached_count        # → integer, cached 10 mins
#   ProductCategory.cached_active_count # → integer, cached 10 mins
#
module Cacheable
  extend ActiveSupport::Concern

  included do
    after_commit :invalidate_cache
  end

  class_methods do
    def cached_count
      Rails.cache.fetch("#{cache_key_prefix}/count", expires_in: 10.minutes) do
        count
      end
    end

    def cached_active_count
      Rails.cache.fetch("#{cache_key_prefix}/active_count", expires_in: 10.minutes) do
        where(active: true).count
      end
    end

    def cache_key_prefix
      "#{name.underscore}"
    end

    def invalidate_model_cache
      Rails.cache.delete_matched("#{cache_key_prefix}/*")
    rescue NotImplementedError
      # Memory store doesn't support delete_matched — safe to ignore
      Rails.cache.delete("#{cache_key_prefix}/count")
      Rails.cache.delete("#{cache_key_prefix}/active_count")
    end
  end

  private

  def invalidate_cache
    self.class.invalidate_model_cache
  end
end