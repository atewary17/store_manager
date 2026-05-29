module Suppliers
  module AsianPaints
    # Matches invoice items to products by material_code only.
    # HSN-looking codes (4-8 pure digits, or HSN- prefixed) are stripped — AP
    # material codes are always alphanumeric with more than 8 characters.
    class Matcher < Suppliers::Base::Matcher
      def self.call(items, organisation)
        codes = items.map { |i| display_code(i) }.compact
        product_map = Product.includes(:base_uom)
                             .for_org(organisation)
                             .where(material_code: codes)
                             .index_by(&:material_code)
        {
          product_map:  product_map,
          match_key_fn: ->(item) { Suppliers::AsianPaints::Matcher.display_code(item) }
        }
      end

      def self.find_product(metadata, organisation)
        code = display_code(metadata)
        return nil if code.blank?
        Product.for_org(organisation)
               .find_by('LOWER(TRIM(material_code)) = LOWER(TRIM(?))', code)
      end

      def self.display_code(item)
        sanitise(item['material_code'].to_s)
      end

      def self.sanitise(raw)
        return nil if raw.blank?
        code = raw.to_s.strip
        return nil if code.match?(/\AHSN[-\s]/i)
        return nil if code.match?(/\A\d{4,8}\z/)
        code
      end
    end
  end
end
