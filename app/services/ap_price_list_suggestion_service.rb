# app/services/ap_price_list_suggestion_service.rb
#
# Decodes an Asian Paints material code and does independent price list lookups
# for each component. Returns a structured suggestion hash for the product
# review UI — purely informational, no saves.
#
# Material code layout (11 chars):
#   chars 0-3  → prod_code  (product line)
#   chars 4-7  → shade_code (shade/colour)
#   chars 8-10 → pack_code  (looked up in AP pack codes JSON)
#
# Each component is looked up independently across ALL rows up to today,
# taking the most recent row. This handles products that live on different
# import dates.

class ApPriceListSuggestionService

  AP_PACK_CODES    = JSON.parse(
    File.read(Rails.root.join('config/asian_paints_pack_codes.json'))
  ).freeze
  VALID_CODE_REGEX = /\A[A-Z0-9]{11}\z/i

  # Maps keywords in AP product line names to product categories.
  AP_CATEGORY_MAP = {
    /\b(damp.?proof|hydro|moisture.?shield|smartcare)\b/i  => 'Waterproofing',
    /\b(wood.?tech|touchwood|wood.?finish|wood.?coat)\b/i  => 'Wood Finishes',
    /\b(lacquer|varnish|wood.?stain)\b/i                   => 'Wood Finishes',
    /\b(thinner|turpentine|solvent)\b/i                    => 'Thinners & Solvents',
    /\b(putty|wall.?care)\b/i                              => 'Putty & Primers',
    /\b(primer)\b/i                                        => 'Putty & Primers',
    /\b(enamel|apcolite|gloss)\b/i                         => 'Paints',
    /\b(royale|tractor|ace|apex|beauty|emulsion)\b/i       => 'Paints',
  }.freeze

  def self.build(product)
    new(product).build
  end

  def initialize(product)
    @product = product
  end

  def build
    code = @product.material_code.to_s.strip
    return nil unless code.match?(VALID_CODE_REGEX)

    prod_code  = code[0..3]
    shade_code = code[4..7]
    pack_code  = code[8..10]

    base_scope = PriceListRow.where('effective_date <= ?', Date.today)

    product_lines = resolve_product_lines(base_scope, prod_code)
    shade         = resolve_shade(base_scope, shade_code)
    pack          = resolve_pack(pack_code)
    brand         = resolve_brand(base_scope, prod_code)
    category_hint = resolve_category_hint(product_lines.first)
    dealer_price  = resolve_dealer_price(base_scope, prod_code, shade_code)

    found_count = [product_lines.any?, shade[:found], pack[:found]].count(true)
    confidence  = case found_count
                  when 3 then :high
                  when 2 then :medium
                  when 1 then :low
                  else        :none
                  end

    {
      material_code:  code,
      prod_code:      prod_code,
      shade_code:     shade_code,
      pack_code:      pack_code,
      product_lines:  product_lines,
      shade:          shade,
      pack:           pack,
      brand:          brand,
      category_hint:  category_hint,
      dealer_price:   dealer_price,
      confidence:     confidence
    }
  end

  private

  def resolve_product_lines(scope, prod_code)
    scope.where(prod_code: prod_code)
         .where.not(product_base_name: [nil, ''])
         .order(effective_date: :desc)
         .pluck(:product_base_name)
         .uniq
  end

  def resolve_shade(scope, shade_code)
    row = scope.where(shade_code: shade_code)
               .where.not(shade_name: [nil, ''])
               .order(effective_date: :desc)
               .first
    return { found: false, value: nil, candidates: [], row_id: nil } unless row

    candidates = row.shade_name.split(',').map(&:strip).reject(&:blank?)
    { found: true, value: candidates.first, candidates: candidates, row_id: row.id }
  end

  def resolve_pack(pack_code)
    info = AP_PACK_CODES[pack_code]
    return { found: false, desc: nil, litres: nil, is_tinting_base: false } unless info

    { found:           true,
      desc:            info['pack_size_desc'],
      litres:          info['pack_size_litres'],
      is_tinting_base: info['is_tinting_base'] }
  end

  def resolve_brand(scope, prod_code)
    row = scope.where(prod_code: prod_code)
               .where.not(brand_id: nil)
               .includes(:brand)
               .order(effective_date: :desc)
               .first
    return { found: false, value: nil } unless row&.brand

    { found: true, value: row.brand.name, brand_id: row.brand_id }
  end

  def resolve_category_hint(product_line_name)
    return { found: false, value: nil } if product_line_name.blank?

    AP_CATEGORY_MAP.each do |pattern, cat|
      return { found: true, value: cat } if product_line_name.match?(pattern)
    end

    # Default for any AP paint line not matched above
    { found: true, value: 'Paints' }
  end

  # Dealer price matched by prod_code + shade_code only — price list pack_code
  # is stored as a litre value ("4.000") which differs from the decoded 3-char
  # AP pack code ("290"), so pack matching is skipped here.
  def resolve_dealer_price(scope, prod_code, shade_code)
    row = scope.where(prod_code: prod_code, shade_code: shade_code)
               .where.not(dealer_price: nil)
               .order(effective_date: :desc)
               .first
    row&.dealer_price
  end

end
