module Suppliers
  module Base
    class Profile
      def slug;           raise NotImplementedError, "#{self.class}#slug"; end
      def display_name;   raise NotImplementedError, "#{self.class}#display_name"; end

      def icon_initials;  '?';    end
      def icon_colour;    '#888'; end
      def tagline;        'Works for any supplier'; end
      def column_set;     :generic; end
      def display_order;  99; end
      def aliases;        []; end

      def matcher;    Suppliers::Generic::Matcher;    end
      def validator;  Suppliers::Generic::Validator;  end
    end
  end
end
