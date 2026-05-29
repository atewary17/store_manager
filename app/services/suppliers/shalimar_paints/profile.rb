module Suppliers
  module ShalimarPaints
    class Profile < Suppliers::Base::Profile
      def slug;           'shalimar_paints'; end
      def display_name;   'Shalimar Paints Limited'; end
      def icon_initials;  'SP'; end
      def icon_colour;    '#f59e0b'; end
      def tagline;        'Pack-size based matching'; end
      def column_set;     :pack_based; end
      def display_order;  2; end
      def aliases;        ['shalimar paints', 'shalimar', 'sp']; end
      def matcher;        Suppliers::ShalimarPaints::Matcher; end
      def validator;      Suppliers::ShalimarPaints::Validator; end
    end
  end
end
