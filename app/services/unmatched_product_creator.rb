# app/services/unmatched_product_creator.rb
#
# Called from PurchaseInvoice#confirm! for every item that has no product_id.
# Creates a Product + OrganisationProduct marked under_review: true so stock can
# be tracked immediately, while a SuperAdmin reviews and approves or merges later.
#
# Usage:
#   product = UnmatchedProductCreator.call(item: purchase_invoice_item,
#                                          organisation: organisation)
#   # Returns the newly created Product, or raises on hard failure.

class UnmatchedProductCreator

  def self.call(item:, organisation:)
    new(item: item, organisation: organisation).call
  end

  def initialize(item:, organisation:)
    @item         = item
    @organisation = organisation
    @meta         = item.metadata.with_indifferent_access
  end

  def call
    brand    = resolve_brand
    uom      = resolve_uom
    category = resolve_category
    gst_rate = Product.nearest_gst_rate(@meta['gst_rate'] || @item.gst_rate)

    description = build_description

    product = Product.create!(
      description:      description,
      material_code:    presence(@meta['material_code']),
      hsn_code:         presence(@meta['hsn_code']),
      gst_rate:         gst_rate,
      brand:            brand,
      product_category: category,
      base_uom:         uom,
      mrp:              nil,
      active:           false,
      under_review:     true,
      catalogue_status: 'under_review',
      source:           'pi_scan',
      metadata: {
        raw_description:  @meta['description'],
        pack_size:        @meta['pack_size'],
        brand_hint:       @meta['brand_name'],
        category_hint:    @meta['category'],
        uom_hint:         @meta['unit'],
        created_from_pi:  true
      }.compact
    )

    # Enrol in the organisation's catalogue (inactive/under_review until approved)
    @organisation.nil? ? product.organisation_products.create! : product.enrol_in!(@organisation)

    # Stamp product_id on the item so the stock ledger loop in confirm! picks it up.
    # Keep unmatched: true — the product is not yet approved for sales.
    @item.update_columns(product_id: product.id)

    Rails.logger.info "[UnmatchedProductCreator] Created product ##{product.id} " \
                      "(#{product.description}) for org #{@organisation&.id}, " \
                      "item #{@item.id}"

    product
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[UnmatchedProductCreator] Failed to create product for item " \
                       "#{@item.id}: #{e.message} | meta=#{@meta.inspect}"
    raise
  end

  private

  # ── Master data resolution (fuzzy → token scan → Others fallback) ───

  def resolve_brand
    # 1. Explicit brand field in metadata (manual entry or future AI extraction)
    raw = [@meta['brand_name'], @meta['brand']].find(&:present?)
    found = Brand.match_fuzzy(raw) if raw.present?
    return found if found && found.name != 'Others'

    # 2. Scan description/supplier tokens — e.g. "AP APCO GLS ENML" → alias "ap" → Asian Paints
    found = brand_from_description_tokens
    return found if found

    Brand.others
  end

  def resolve_uom
    raw = [@meta['unit'], @meta['uom']].find(&:present?)
    Uom.match_fuzzy(raw) || Uom.others
  end

  def resolve_category
    # 1. Explicit category field in metadata
    raw = [@meta['category'], @meta['product_category']].find(&:present?)
    found = ProductCategory.match_fuzzy(raw) if raw.present?
    return found if found && found.name != 'Others'

    # 2. Infer from description keywords
    found = category_from_description
    return found if found

    ProductCategory.match_fuzzy(build_description) || ProductCategory.others
  end

  # Try every word-token in the description against brand names/aliases.
  # Stops at the first unambiguous match (name != "Others").
  def brand_from_description_tokens
    desc = [@meta['description'], @meta['raw_description'],
            @meta['brand_name']].find(&:present?).to_s
    return nil if desc.blank?

    # Try each token individually (handles "AP", "BERGER", "ASIAN" etc.)
    desc.split(/[\s\-\/,]+/).each do |token|
      next if token.length < 2
      b = Brand.match_fuzzy(token.downcase)
      return b if b && b.name != 'Others'
    end

    # Try the first two tokens together (handles "ASIAN PAINTS", "BERGER PAINT" etc.)
    words = desc.split(/[\s\-\/,]+/).first(3)
    (2..words.length).each do |n|
      b = Brand.match_fuzzy(words.first(n).join(' ').downcase)
      return b if b && b.name != 'Others'
    end

    nil
  end

  # Map common paint/hardware keywords in the description to category names.
  CATEGORY_KEYWORDS = {
    /\b(emulsion|enamel|primer|distemper|putty|varnish|lacquer|stain|wood\s*finish|texture|paint|coating|weathershield)\b/i => 'Paints',
    /\b(brush|roller|masking\s*tape|painting\s*tool|paint\s*tray)\b/i                                                        => 'Painting Accessories',
    /\b(thinner|turpentine|solvent|mineral\s*spirit)\b/i                                                                     => 'Thinners & Solvents',
    /\b(waterproof|dampproof|damp\s*proof|water\s*proof)\b/i                                                                 => 'Waterproofing',
    /\b(pipe|fitting|tap|valve|elbow|reducer|coupling|plumb)\b/i                                                             => 'Plumbing',
    /\b(wire|cable|switch|socket|mcb|rcd|breaker|conduit)\b/i                                                                => 'Electrical',
    /\b(screw|nail|bolt|nut|washer|rivet|anchor|rawl)\b/i                                                                    => 'Fasteners',
    /\b(hinge|lock|handle|knob|latch|deadbolt|padlock)\b/i                                                                   => 'Locks & Hinges',
    /\b(adhesive|sealant|silicone|fevicol|epoxy|grout|bond)\b/i                                                              => 'Adhesives & Sealants',
    /\b(cement|concrete|mortar|plaster)\b/i                                                                                  => 'Cement & Concrete',
    /\b(tile|tiles|ceramic|vitrified|mosaic|flooring)\b/i                                                                    => 'Tiles',
    /\b(drill|grinder|sander|jigsaw|circular\s*saw|power\s*tool)\b/i                                                        => 'Power Tools',
    /\b(hammer|wrench|plier|chisel|saw|spanner|screwdriver|hand\s*tool)\b/i                                                  => 'Hand Tools',
  }.freeze

  def category_from_description
    desc = [@meta['description'], @meta['raw_description']].find(&:present?).to_s
    return nil if desc.blank?

    CATEGORY_KEYWORDS.each do |pattern, cat_name|
      next unless desc.match?(pattern)
      cat = ProductCategory.find_by(name: cat_name)
      return cat if cat
    end

    nil
  end

  # ── Description builder ──────────────────────────────────────

  def build_description
    # Prefer explicit description field; fall back to a concatenation of
    # available signals so the product is identifiable in the review queue.
    desc = presence(@meta['description']) ||
           presence(@meta['raw_description'])
    return desc if desc.present?

    parts = [
      @meta['brand_name'],
      @meta['material_code'],
      @meta['pack_size']
    ].compact.map(&:presence).compact
    parts.any? ? parts.join(' ') : 'Unknown Product (from scan)'
  end

  def presence(val)
    val.to_s.strip.presence
  end

end
