module Suppliers
  module Base
    # Interface every supplier validator must honour.
    #
    # .call(items)
    #   → { items: Array<item_with_flags>, flags: Hash<sr_no, [messages]>, valid: Boolean }
    #
    class Validator
      TOLERANCE = 1.0

      def self.call(items)
        annotated = Array(items).map { |i| i.merge('_flags' => []) }
        { items: annotated, flags: {}, valid: true }
      end
    end
  end
end
