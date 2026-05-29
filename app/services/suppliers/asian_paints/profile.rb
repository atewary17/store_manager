module Suppliers
  module AsianPaints
    class Profile < Suppliers::Base::Profile
      def slug;           'asian_paints'; end
      def display_name;   'Asian Paints Limited'; end
      def icon_initials;  'AP'; end
      def icon_colour;    '#ef4444'; end
      def tagline;        'Optimised column mapping'; end
      def column_set;     :standard; end
      def display_order;  1; end
      def aliases;        ['asian paints', 'ap']; end
      def matcher;        Suppliers::AsianPaints::Matcher; end
      def validator;      Suppliers::AsianPaints::Validator; end
    end
  end
end
