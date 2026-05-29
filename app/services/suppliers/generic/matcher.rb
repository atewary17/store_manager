module Suppliers
  module Generic
    # Description-based matcher for generic / tally invoices.
    #
    # Strategy — reverse match:
    #   "Does the invoice description contain the product name?"
    #   i.e. LOWER(description) LIKE LOWER('%' || product.name || '%')
    #
    # Only commits when exactly ONE product matches — ambiguous results stay UNMATCHED.
    # No material_code involvement: display_code returns nil for all Generic items.
    #
    class Matcher < Suppliers::Base::Matcher
      def self.call(items, organisation)
        product_map = {}
        items.each do |item|
          key = item_key(item)
          next if key.blank?
          product = find_by_description(item['description'].to_s, organisation)
          product_map[key] = product if product
        end
        {
          product_map:  product_map,
          match_key_fn: ->(item) { Suppliers::Generic::Matcher.item_key(item) }
        }
      end

      def self.find_product(metadata, organisation)
        return nil unless organisation
        find_by_description(metadata['description'].to_s, organisation)
      end

      def self.display_code(_item)
        nil
      end

      def self.item_key(item)
        item['description'].to_s.strip.presence
      end

      private_class_method def self.find_by_description(description, organisation)
        return nil if description.blank?

        results = Product.for_org(organisation)
                         .where("LOWER(?) LIKE LOWER('%' || TRIM(products.description) || '%')", description.strip)
        results.count == 1 ? results.first : nil
      end
    end
  end
end
