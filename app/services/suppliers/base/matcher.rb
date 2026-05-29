module Suppliers
  module Base
    # Interface every supplier matcher must honour.
    #
    # .call(items, organisation)
    #   → { product_map: Hash<key, Product>, match_key_fn: Lambda<item→key> }
    #
    # .find_product(metadata, organisation)
    #   → Product | nil   (used by PurchaseInvoiceItem#resolve_product at save time)
    #
    # .display_code(item)
    #   → String | nil    (what to show/submit as material_code in the review form)
    #
    class Matcher
      def self.call(_items, _organisation)
        { product_map: {}, match_key_fn: ->(_item) { nil } }
      end

      def self.find_product(_metadata, _organisation)
        nil
      end

      def self.display_code(item)
        item['material_code'].to_s.presence
      end
    end
  end
end
