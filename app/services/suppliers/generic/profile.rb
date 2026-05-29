module Suppliers
  module Generic
    class Profile < Suppliers::Base::Profile
      def slug;           'generic'; end
      def display_name;   'Others'; end
      def icon_initials;  '?'; end
      def icon_colour;    '#6b7280'; end
      def tagline;        'Works for any supplier'; end
      def column_set;     :generic; end
      def display_order;  99; end
      def aliases;        ['generic', 'other', 'others', 'unknown']; end
      def matcher;        Suppliers::Generic::Matcher; end
      def validator;      Suppliers::Generic::Validator; end
    end
  end
end
