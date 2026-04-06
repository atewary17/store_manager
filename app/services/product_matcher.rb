# app/services/product_matcher.rb
#
# Three-pass product matching engine.
# Called from purchase invoice product_search and digitise confirm flow.
#
# Pass 1 — Exact:  material_code exact match (case-insensitive, trimmed)
# Pass 2 — Fuzzy:  pg_trgm similarity on description (threshold: 0.4)
# Pass 3 — None:   No match found → caller should trigger AI enrichment
#
# Returns a MatchResult value object:
#   result.product      → Product or nil
#   result.match_type   → :exact | :fuzzy | :none
#   result.similarity   → Float (0..1), present for fuzzy match
#   result.matched?     → true if pass 1 or 2 succeeded

class ProductMatcher

  FUZZY_THRESHOLD = 0.35  # pg_trgm similarity — tunable

  MatchResult = Struct.new(:product, :match_type, :similarity, keyword_init: true) do
    def matched?     = match_type != :none
    def exact?       = match_type == :exact
    def fuzzy?       = match_type == :fuzzy
    def unmatched?   = match_type == :none
    def pending?
      product.present? &&
        !product.active? &&
        product.metadata&.dig('source') == 'ai_enrichment'
    end
  end

  # ── Public entry point ────────────────────────────────────────
  # material_code: String or nil
  # description:   String or nil
  # Returns MatchResult
  def self.match(material_code, description)
    new(material_code, description).match
  end

  def initialize(material_code, description)
    @material_code = sanitise_code(material_code)
    @description   = description.to_s.strip
  end

  def match
    # Pass 1 — exact material_code
    if @material_code.present?
      p = exact_match(@material_code)
      return MatchResult.new(product: p, match_type: :exact, similarity: 1.0) if p
    end

    # Pass 2 — fuzzy description (only if we have a meaningful description)
    if @description.length >= 4
      result = fuzzy_match(@description)
      if result
        return MatchResult.new(
          product:    result[:product],
          match_type: :fuzzy,
          similarity: result[:similarity]
        )
      end
    end

    # Pass 3 — no match
    MatchResult.new(product: nil, match_type: :none, similarity: 0.0)
  end

  private

  # ── Pass 1: exact material_code (active products first, then pending) ──
  def exact_match(code)
    # Try active products first
    p = Product.where('LOWER(TRIM(material_code)) = LOWER(?)', code).where(active: true).first
    return p if p

    # Also check AI-enriched pending products — shopkeeper may re-order the same item
    Product.where('LOWER(TRIM(material_code)) = LOWER(?)', code)
           .where(active: false)
           .where("metadata->>'source' = 'ai_enrichment'")
           .first
  end

  # ── Pass 2: pg_trgm similarity on description ─────────────────
  def fuzzy_match(description)
    return nil unless trgm_available?

    results = Product
      .where(active: true)
      .where(
        'similarity(LOWER(products.description), LOWER(?)) > ?',
        description, FUZZY_THRESHOLD
      )
      .select("products.*, similarity(LOWER(products.description), LOWER(#{Product.connection.quote(description)})) AS trgm_score")
      .order('trgm_score DESC')
      .limit(1)

    return nil if results.empty?

    best = results.first
    score = best.try(:trgm_score).to_f

    score > FUZZY_THRESHOLD ? { product: best, similarity: score } : nil
  rescue ActiveRecord::StatementInvalid
    # pg_trgm not available or query failed — skip fuzzy pass gracefully
    nil
  end

  # ── Helpers ───────────────────────────────────────────────────
  def sanitise_code(raw)
    return nil if raw.blank?
    cleaned = raw.to_s.strip
    # Remove leading zeros that are clearly HSN contamination (8+ digit pure numbers)
    # but KEEP codes like "0026" or "AP-001" — only strip if it looks like HSN bleeding
    cleaned.presence
  end

  def trgm_available?
    @trgm_available ||= begin
      ActiveRecord::Base.connection.execute(
        "SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm'"
      ).any?
    rescue
      false
    end
  end

end
