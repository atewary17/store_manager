module Suppliers
  class Registry
    # Ordered list of all registered supplier profiles.
    # To add a new supplier: append its Profile class here + create the directory.
    PROFILES = [
      Suppliers::AsianPaints::Profile,
      Suppliers::ShalimarPaints::Profile,
      Suppliers::Generic::Profile,
    ].freeze

    # Returns the best-matching Profile instance for a supplier hint string.
    # Falls back to Generic if no match found.
    def self.for(supplier_hint)
      norm = normalise(supplier_hint.to_s)
      return Suppliers::Generic::Profile.new if norm.blank?

      PROFILES.each do |klass|
        profile = klass.new
        return profile if normalise(profile.display_name) == norm
        return profile if norm.include?(normalise(profile.slug.gsub('_', ' ')))
        profile.aliases.each { |a| return profile if norm.include?(normalise(a)) }
      end

      Suppliers::Generic::Profile.new
    end

    # Returns all registered profiles ordered by display_order.
    # Used by the upload form to generate supplier option cards.
    def self.all
      PROFILES.map(&:new).sort_by(&:display_order)
    end

    def self.normalise(str)
      str.to_s.downcase.gsub(/[^a-z0-9\s]/, '').strip
    end
    private_class_method :normalise
  end
end
