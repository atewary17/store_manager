# app/services/org_product_filter_service.rb
#
# Builds an org-scoped product profile filter from their inventory history
# and stores it in organisations.settings['product_filter'].
#
# Isolation: all queries are scoped to a single organisation — this service
# never reads another org's data. The filter is written to that org's own
# settings column.
#
# Usage:
#   result = OrgProductFilterService.call(organisation)
#   # => { brands: [...], categories: [...], product_count: 142, ... }

class OrgProductFilterService

  # Keywords that identify specific product types from descriptions/metadata.
  PRODUCT_TYPE_KEYWORDS = {
    'primer'        => /\bprimer\b/i,
    'putty'         => /\bputty\b/i,
    'tintable_base' => /tint(able)?\s*base|\bTB\b/i,
    'colourant'     => /\bcolou?rant\b/i,
    'emulsion'      => /\bemulsion\b/i,
    'enamel'        => /\benamel\b/i,
    'distemper'     => /\bdistemper\b/i,
    'varnish'       => /\bvarnish\b/i,
    'weathercoat'   => /\bweathercoat\b|\bweather\s*shield\b/i,
    'wood_finish'   => /\bwood.?(?:tech|finish|coat|stain)\b/i,
  }.freeze

  def self.call(organisation)
    new(organisation).call
  end

  def initialize(organisation)
    @org = organisation
  end

  def call
    # Source: products that have a StockLevel record for this org.
    # This is the same set shown on the stock dashboard — not the wider
    # organisation_products catalogue which may include unenrolled products.
    stocked_ids = StockLevel.where(organisation_id: @org.id).select(:product_id)
    products    = Product
                    .where(id: stocked_ids)
                    .includes(:brand, :product_category)

    brands = products
               .filter_map { |p| p.brand&.name }
               .uniq
               .reject { |n| n.downcase == 'others' }
               .sort

    categories = products
                   .filter_map { |p| p.product_category&.name }
                   .uniq
                   .reject { |n| n.downcase == 'others' }
                   .sort

    pack_sizes = products
                   .filter_map { |p| p.metadata['pack_size_desc'].presence }
                   .uniq
                   .sort_by { |s| pack_sort_key(s) }

    product_types = PRODUCT_TYPE_KEYWORDS.filter_map do |type, pattern|
      desc_match = products.any? { |p|
        p.description.to_s.match?(pattern) ||
        p.metadata['product_line_desc'].to_s.match?(pattern)
      }
      type if desc_match
    end.sort

    supplier_hints = resolve_supplier_hints

    existing = @org.settings['product_filter']
    is_new   = existing.blank?

    filter = {
      'brands'         => brands,
      'categories'     => categories,
      'pack_sizes'     => pack_sizes,
      'product_types'  => product_types,
      'supplier_hints' => supplier_hints,
      'product_count'  => products.size,
      'first_built_at' => existing&.dig('first_built_at') || Time.current.iso8601,
      'last_built_at'  => Time.current.iso8601
    }

    @org.update!(settings: @org.settings.merge('product_filter' => filter))

    Rails.logger.info "[OrgProductFilter] #{is_new ? 'Built' : 'Updated'} filter for " \
                      "org ##{@org.id} (#{@org.name}) — #{products.size} products, " \
                      "#{brands.size} brands, #{categories.size} categories"

    { filter: filter, new_filter: is_new }
  rescue => e
    Rails.logger.error "[OrgProductFilter] Failed for org ##{@org.id}: #{e.message}"
    raise
  end

  private

  # Pull distinct supplier_hint values from PI items for this org.
  # Isolated to this org's purchase invoices only.
  def resolve_supplier_hints
    PurchaseInvoiceItem
      .joins(:purchase_invoice)
      .where(purchase_invoices: { organisation_id: @org.id })
      .where("purchase_invoice_items.metadata->>'supplier_hint' IS NOT NULL")
      .where("purchase_invoice_items.metadata->>'supplier_hint' != ''")
      .distinct
      .pluck(Arel.sql("purchase_invoice_items.metadata->>'supplier_hint'"))
      .compact.uniq.sort
  rescue
    []
  end

  # Sort pack sizes by volume for sensible display order.
  def pack_sort_key(desc)
    return 0 if desc.blank?
    m = desc.match(/(\d+(?:\.\d+)?)\s*(ml|litre?s?|ltr?|l\b)/i)
    return 999 unless m
    val = m[1].to_f
    unit = m[2].downcase
    unit.start_with?('ml') ? val / 1000.0 : val
  end

end
