# app/services/product_similarity_service.rb
#
# Computes weighted similarity between an under_review product and active products
# in the global catalogue. Used by the SuperAdmin review dashboard.
#
# Weights (must sum to 1.0):
#   material_code    35% — most unique identifier; exact match only
#   internet_details 20% — AI-enriched structured data (Groq)
#   hsn_code         15% — exact HSN match narrows to same category
#   brand            15% — same brand_id
#   description      10% — pg_trgm trigram similarity (noisy)
#   pack_size         5% — supporting signal only
#
# Usage:
#   matches = ProductSimilarityService.find_matches(under_review_product)
#   # => [ [product, { total: 0.87, material_code: 1.0, brand: 1.0, ... }], ... ]

class ProductSimilarityService

  WEIGHTS = {
    material_code:    0.35,
    internet_details: 0.20,
    hsn_code:         0.15,
    brand:            0.15,
    description:      0.10,
    pack_size:        0.05
  }.freeze

  MIN_TOTAL_SCORE = 0.20  # hide matches below 20% — noise

  def self.find_matches(product, limit: 10)
    new(product).find_matches(limit: limit)
  end

  def initialize(product)
    @product = product
  end

  def find_matches(limit: 10)
    candidates = gather_candidates
    return [] if candidates.empty?

    candidates
      .map  { |c| [c, score(@product, c)] }
      .select { |_, s| s[:total] >= MIN_TOTAL_SCORE }
      .sort_by { |_, s| -s[:total] }
      .first(limit)
  end

  private

  # ── Candidate gathering (SQL pre-filter, then score in Ruby) ──────────────
  # Cast a wide net via separate SQL queries per signal, deduplicate IDs,
  # then load all candidates in one query with associations.

  def gather_candidates
    id_sets = []

    # Exact material_code
    if @product.material_code.present?
      id_sets += Product.active
                        .where('LOWER(TRIM(material_code)) = LOWER(TRIM(?))', @product.material_code)
                        .pluck(:id)
    end

    # Description trigram (low threshold — scored properly in Ruby)
    if @product.description.present?
      id_sets += Product.active
                        .where('similarity(LOWER(description), ?) > 0.20',
                               @product.description.downcase)
                        .pluck(:id)
    end

    # Same brand (if not "Others")
    if @product.brand_id.present? && @product.brand&.name&.downcase != 'others'
      id_sets += Product.active.where(brand_id: @product.brand_id).limit(30).pluck(:id)
    end

    # Same HSN
    if @product.hsn_code.present?
      id_sets += Product.active.where(hsn_code: @product.hsn_code).limit(20).pluck(:id)
    end

    # Internet details: if AI enrichment found a brand_guess or description, use it
    enrichment = @product.internet_details&.dig('groq_enrichment')
    if enrichment.present?
      if enrichment['description'].present?
        id_sets += Product.active
                          .where('similarity(LOWER(description), ?) > 0.20',
                                 enrichment['description'].to_s.downcase)
                          .pluck(:id)
      end
      if enrichment['material_code'].present?
        id_sets += Product.active
                          .where('LOWER(TRIM(material_code)) = LOWER(TRIM(?))',
                                 enrichment['material_code'])
                          .pluck(:id)
      end
    end

    return [] if id_sets.empty?

    Product.active
           .where(id: id_sets.uniq)
           .where.not(id: @product.id)
           .includes(:brand, :product_category, :base_uom)
           .limit(50)
           .to_a
  end

  # ── Full scoring ──────────────────────────────────────────────────────────

  def score(a, b)
    s = {
      material_code:    code_score(a.material_code, b.material_code),
      hsn_code:         exact_score(a.hsn_code, b.hsn_code),
      brand:            exact_score(a.brand_id, b.brand_id),
      description:      trgm_score(a.description, b.description),
      internet_details: internet_score(a.internet_details, b),
      pack_size:        exact_score(a.metadata['pack_size'], b.metadata['pack_size'])
    }
    total = WEIGHTS.sum { |field, w| s[field] * w }.round(3)
    s.merge(total: total)
  end

  # Exact code match only — no partial credit (partial code matches are noise)
  def code_score(a, b)
    return 0.0 if a.blank? || b.blank?
    a.to_s.strip.downcase == b.to_s.strip.downcase ? 1.0 : 0.0
  end

  def exact_score(a, b)
    return 0.0 if a.blank? || b.blank?
    a.to_s.strip.downcase == b.to_s.strip.downcase ? 1.0 : 0.0
  end

  def trgm_score(a, b)
    return 0.0 if a.blank? || b.blank?
    Product.connection.select_value(
      "SELECT similarity(#{quote(a.downcase)}, #{quote(b.downcase)})"
    ).to_f.round(3)
  rescue
    0.0
  end

  # Compare AI enrichment fields from under_review product against candidate's
  # live attributes. Only one side (a) has internet_details in practice.
  def internet_score(internet_details, candidate)
    enrichment = internet_details&.dig('groq_enrichment')
    return 0.0 if enrichment.blank?

    checks = 0
    matched = 0

    if enrichment['brand_guess'].present? && candidate.brand.present?
      checks += 1
      matched += 1 if candidate.brand.name.downcase == enrichment['brand_guess'].downcase
    end

    if enrichment['hsn_code'].present? && candidate.hsn_code.present?
      checks += 1
      matched += 1 if candidate.hsn_code == enrichment['hsn_code']
    end

    if enrichment['description'].present? && candidate.description.present?
      checks += 1
      trgm = trgm_score(enrichment['description'], candidate.description)
      matched += trgm  # partial credit
    end

    if enrichment['material_code'].present? && candidate.material_code.present?
      checks += 1
      matched += 1 if candidate.material_code.downcase == enrichment['material_code'].downcase
    end

    checks > 0 ? (matched.to_f / checks).round(3) : 0.0
  end

  def quote(str)
    Product.connection.quote(str.to_s)
  end

end
