# app/jobs/ap_price_list_sync_job.rb
#
# Enriches existing Asian Paints products from staged price list rows.
# Never creates products. Never touches product.description.
# Only updates metadata and blank column fields (shade_code, product_code, pack_code).
# Runs rules 1–4 per product; stops at first matched/partial result.
# One ApPriceListSyncLog entry is written per product per run.

class ApPriceListSyncJob < ApplicationJob
  queue_as :enrichment

  retry_on StandardError, wait: 5.minutes, attempts: 2

  def perform(import_batch_id: nil, triggered_by_user_id: nil)
    @triggered_by_user_id = triggered_by_user_id
    @run_at               = Time.current

    products = load_ap_products
    Rails.logger.info "[ApPriceListSyncJob] Starting — #{products.size} AP products to process"

    products.each do |product|
      process_product(product, import_batch_id)
    rescue => e
      Rails.logger.error "[ApPriceListSyncJob] product ##{product.id} failed: #{e.message}"
      write_log(
        product:    product,
        rule:       0,
        status:     'unmatched',
        confidence: 'none',
        notes:      "Unexpected error: #{e.message}"
      )
    end

    Rails.logger.info "[ApPriceListSyncJob] Completed"
  end

  private

  # ── Product loading ────────────────────────────────────────────────────────

  def load_ap_products
    Product
      .joins(:brand)
      .where('LOWER(brands.name) = ?', 'asian paints')
      .where(active: true)
      .includes(:brand)
  end

  # ── Per-product orchestration ──────────────────────────────────────────────

  def process_product(product, import_batch_id)
    if already_matched?(product)
      write_log(product: product, rule: 0, status: 'already_matched',
                confidence: 'high', notes: 'Skipped — already matched in previous run')
      return
    end

    @row_scope = scoped_rows(import_batch_id)

    result = run_rule1(product) ||
             run_rule2(product) ||
             run_rule3(product) ||
             run_rule4(product)

    # Retry up to 2 more times for transient save failures (e.g. brief DB lock).
    if result == :save_failed
      2.times do |attempt|
        break unless result == :save_failed
        sleep(0.5 * (attempt + 1))
        product.reload
        result = run_rule1(product) ||
                 run_rule2(product) ||
                 run_rule3(product) ||
                 run_rule4(product)
      end
    end

    result
  end

  def already_matched?(product)
    product.metadata&.dig('price_list_matched_at').present? &&
      PriceListRow.where(matched_product_id: product.id, match_status: 'matched').exists?
  end

  def scoped_rows(import_batch_id)
    if import_batch_id.present?
      batch = PriceListImport.find_by(id: import_batch_id)
      if batch
        PriceListRow.where(imported_at: batch.created_at.beginning_of_minute..batch.completed_at.end_of_minute)
      else
        PriceListRow.all
      end
    else
      latest = PriceListRow.maximum(:effective_date)
      latest ? PriceListRow.where(effective_date: latest) : PriceListRow.none
    end
  end

  # ── Rule 1: Three-field exact match ────────────────────────────────────────

  def run_rule1(product)
    return nil unless product.product_code.present? &&
                      product.pack_code.present? &&
                      product.shade_code.present?

    row = @row_scope.where(
      prod_code:  product.product_code,
      pack_code:  product.pack_code,
      shade_code: product.shade_code
    ).first

    if row.nil?
      row = @row_scope
              .where('LOWER(prod_code) = LOWER(?)',  product.product_code)
              .where('LOWER(pack_code) = LOWER(?)',  product.pack_code)
              .where('LOWER(shade_code) = LOWER(?)', product.shade_code)
              .first
      case_note = row ? 'case mismatch resolved' : nil
    end

    return nil if row.nil?

    enriched, skipped, saved = enrich_product(product, row, rule: 1)
    mark_row_matched(row, product) if saved
    write_log(
      product:    product,
      row:        row,
      rule:       1,
      status:     saved ? 'matched' : 'save_failed',
      confidence: 'high',
      enriched:   enriched,
      skipped:    skipped,
      details:    { prod_code: product.product_code,
                    pack_code: product.pack_code,
                    shade_code: product.shade_code },
      notes:      case_note
    )
    saved ? :matched : :save_failed
  end

  # ── Rule 2: Material code decode, independent field enrichment ─────────────

  def run_rule2(product)
    return nil unless product.material_code.present? &&
                      product.material_code.match?(/\A\d{11}\z/)

    decoded = Product.decode_ap_material_code(product.material_code)
    return nil if decoded.nil?

    dp = decoded[:product_code]
    ds = decoded[:shade_code]
    dk = decoded[:pack_code]

    enriched = []
    skipped  = {}
    meta     = product.metadata.dup

    # Step A — product_line_desc from prod_code
    row_a = @row_scope.where(prod_code: dp)
                      .where.not(product_base_name: [nil, ''])
                      .order(effective_date: :desc).first
    if row_a
      meta['product_line_desc'] = row_a.product_base_name
      enriched << 'product_line_desc'
    end

    # Step B — shade_name + shade_code + is_tinting_base from shade_code.
    # If the price list shade_name is comma-separated (multiple shades share the
    # same shade_code), resolve_shade_name picks the one that best matches the
    # product description using token-level fuzzy matching.
    row_b = @row_scope.where(shade_code: ds)
                      .where.not(shade_name: [nil, ''])
                      .order(effective_date: :desc).first
    if row_b
      resolved_shade          = resolve_shade_name(row_b.shade_name, product.description)
      meta['shade_name']      = resolved_shade
      meta['is_tinting_base'] = tinting_base_shade?(resolved_shade)
      enriched << 'shade_name'
      enriched << 'is_tinting_base'
      if product.shade_code.blank?
        product.shade_code = ds
        enriched << 'shade_code'
      end
    end

    # Step C — pack_size from pack_code
    row_c = @row_scope.where(pack_code: dk)
                      .where.not(pack_size_litres: nil)
                      .order(effective_date: :desc).first
    if row_c
      meta['pack_size_litres'] = row_c.pack_size_litres
      meta['pack_size_desc']   = format_pack_size(row_c.pack_size_litres)
      enriched << 'pack_size_litres'
      enriched << 'pack_size_desc'
    end

    # Step D — dpl_group + dealer_price + price_effective when full 3-field row found
    row_d = @row_scope.where(prod_code: dp, shade_code: ds, pack_code: dk)
                      .order(effective_date: :desc).first
    if row_d
      meta['dpl_group']       = row_d.dpl_group
      meta['dealer_price']    = row_d.dealer_price
      meta['price_effective'] = row_d.effective_date&.iso8601
      enriched += %w[dpl_group dealer_price price_effective]
    end

    return nil if enriched.empty?

    confidence   = row_d ? 'high'    : 'medium'
    match_status = row_d ? 'matched' : 'partial'

    meta.merge!(price_list_audit_fields(rule: 2, confidence: confidence, row: row_d || row_a))
    apply_column_fields(product, row_d || row_a, skipped: skipped)
    product.metadata = meta
    saved = save_product(product, skipped)

    mark_row_matched(row_d, product) if row_d && saved

    final_status = saved ? match_status : 'save_failed'
    write_log(
      product:    product,
      row:        row_d || row_a,
      rule:       2,
      status:     final_status,
      confidence: confidence,
      enriched:   enriched,
      skipped:    skipped,
      details:    { decoded_product_code: dp, decoded_shade_code: ds,
                    decoded_pack_code: dk, full_row_found: row_d.present? }
    )
    final_status.to_sym
  end

  # ── Rule 3: Two-field match, no shade_code ─────────────────────────────────

  def run_rule3(product)
    return nil unless product.product_code.present? && product.pack_code.present?
    return nil if product.shade_code.present?

    rows = @row_scope.where(prod_code: product.product_code, pack_code: product.pack_code)
                     .order(effective_date: :desc)

    if rows.many?
      @row_scope.where(prod_code: product.product_code, pack_code: product.pack_code)
                .update_all(match_status: 'ambiguous')
      write_log(
        product:    product,
        rule:       3,
        status:     'ambiguous',
        confidence: 'low',
        details:    { matching_row_ids: rows.pluck(:id),
                      prod_code: product.product_code,
                      pack_code: product.pack_code },
        notes:      'Multiple price list rows for same product+pack — admin review needed'
      )
      return :ambiguous
    end

    return nil if rows.empty?

    row      = rows.first
    enriched = []
    skipped  = {}
    meta     = product.metadata.dup

    if row.product_base_name.present?
      meta['product_line_desc'] = row.product_base_name
      enriched << 'product_line_desc'
    end
    if row.pack_size_litres.present?
      meta['pack_size_litres'] = row.pack_size_litres
      meta['pack_size_desc']   = format_pack_size(row.pack_size_litres)
      enriched << 'pack_size_litres'
      enriched << 'pack_size_desc'
    end
    if row.dpl_group.present?
      meta['dpl_group'] = row.dpl_group
      enriched << 'dpl_group'
    end
    meta['dealer_price']    = row.dealer_price
    meta['price_effective'] = row.effective_date&.iso8601
    enriched << 'dealer_price'
    enriched << 'price_effective'

    # Shade fields intentionally skipped — two-field match can't confirm shade
    skipped['shade_name']      = 'two-field match — shade not enriched, verify manually'
    skipped['shade_code']      = 'two-field match — shade not enriched, verify manually'
    skipped['is_tinting_base'] = 'two-field match — cannot determine without shade'

    meta.merge!(price_list_audit_fields(rule: 3, confidence: 'medium', row: row))
    apply_column_fields(product, row, skip_shade: true, skipped: skipped)
    product.metadata = meta
    saved = save_product(product, skipped)
    mark_row_matched(row, product) if saved

    write_log(
      product:    product,
      row:        row,
      rule:       3,
      status:     saved ? 'matched' : 'save_failed',
      confidence: 'medium',
      enriched:   enriched,
      skipped:    skipped,
      details:    { prod_code: product.product_code, pack_code: product.pack_code },
      notes:      'Two-field match — shade not enriched, verify manually'
    )
    saved ? :matched : :save_failed
  end

  # ── Rule 4: No match ────────────────────────────────────────────────────────

  def run_rule4(product)
    write_log(
      product:    product,
      rule:       4,
      status:     'unmatched',
      confidence: 'none',
      details:    { material_code: product.material_code,
                    product_code:  product.product_code,
                    pack_code:     product.pack_code,
                    shade_code:    product.shade_code },
      notes:      build_rule4_note(product)
    )
    :unmatched
  end

  def build_rule4_note(product)
    reasons = []
    unless product.product_code.present? && product.pack_code.present? && product.shade_code.present?
      reasons << "Rule 1 skipped: product_code/pack_code/shade_code not all present"
    end
    if product.material_code.present?
      unless product.material_code.match?(/\A\d{11}\z/)
        reasons << "Rule 2 skipped: material_code '#{product.material_code}' is not 11 digits"
      end
    else
      reasons << "Rule 2 skipped: no material_code"
    end
    unless product.product_code.present? && product.pack_code.present?
      reasons << "Rule 3 skipped: product_code or pack_code missing"
    end
    reasons.join(' | ')
  end

  # ── Enrichment helpers ──────────────────────────────────────────────────────

  # Used by Rule 1 (full 3-field match) — all fields available from one row.
  def enrich_product(product, row, rule:)
    enriched = []
    skipped  = {}
    meta     = product.metadata.dup

    {
      'product_line_desc' => row.product_base_name,
      'shade_name'        => row.shade_name,
      'pack_size_litres'  => row.pack_size_litres,
      'pack_size_desc'    => format_pack_size(row.pack_size_litres),
      'dpl_group'         => row.dpl_group,
      'dealer_price'      => row.dealer_price,
      'price_effective'   => row.effective_date&.iso8601
    }.each do |field, value|
      next if value.blank?
      meta[field] = value
      enriched << field
    end

    if row.shade_name.present?
      meta['is_tinting_base'] = tinting_base_shade?(row.shade_name)
      enriched << 'is_tinting_base'
    end

    meta.merge!(price_list_audit_fields(rule: rule, confidence: 'high', row: row))
    apply_column_fields(product, row, skipped: skipped)
    product.metadata = meta
    saved = save_product(product, skipped)

    [enriched, skipped, saved]
  end

  # Only set column fields if currently blank — never overwrite.
  # product_code has a unique DB constraint: pre-check before assigning.
  def apply_column_fields(product, row, skip_shade: false, skipped: {})
    return unless row

    product.shade_code = row.shade_code if product.shade_code.blank? && !skip_shade

    if product.product_code.blank? && row.prod_code.present?
      if Product.where(product_code: row.prod_code).where.not(id: product.id).exists?
        skipped['product_code'] = "conflict — '#{row.prod_code}' already assigned to another product"
      else
        product.product_code = row.prod_code
      end
    end

    product.pack_code = row.pack_code if product.pack_code.blank?
  end

  def price_list_audit_fields(rule:, confidence:, row:)
    {
      'price_list_match_rule'       => rule,
      'price_list_match_confidence' => confidence,
      'price_list_matched_at'       => @run_at.iso8601,
      'price_list_row_id'           => row&.id
    }
  end

  def save_product(product, skipped)
    product.save!(validate: false)
    true
  rescue => e
    skipped['_save_error'] = e.message
    Rails.logger.warn "[ApPriceListSyncJob] save failed for product ##{product.id}: #{e.message}"
    false
  end

  def mark_row_matched(row, product)
    return unless row
    row.update_columns(
      match_status:       'matched',
      matched_product_id: product.id,
      matched_at:         @run_at
    )
  end

  # ── Format helpers ──────────────────────────────────────────────────────────

  def format_pack_size(litres)
    return nil if litres.nil?
    l = litres.to_f
    if l < 1.0
      "#{(l * 1000).round}ml"
    elsif l == 1.0
      "1 Litre"
    else
      "#{l.to_i} Litres"
    end
  end

  # Detects tinting base products from shade name.
  # Asian Paints typically names these "TINTING BASE", "TINT BASE", or appends "TB".
  def tinting_base_shade?(shade_name)
    return false if shade_name.blank?
    shade_name.to_s.match?(/tint(ing)?\s*base|\bTB\b|T\.B\./i)
  end

  # ── Shade name disambiguation ────────────────────────────────────────────────

  # When a price list shade_name is comma-separated (multiple shade names share
  # the same shade_code), pick the candidate that best matches the product
  # description. Falls back to the first candidate if nothing scores above zero.
  #
  # Example:
  #   shade_name_raw = "OxBlue, Bus Green, Brown, Golden brown"
  #   description    = "AP APCO GLS ENML OX BLUE 100ML"
  #   → returns "OxBlue"
  def resolve_shade_name(shade_name_raw, description)
    return shade_name_raw if shade_name_raw.blank?

    candidates = shade_name_raw.split(',').map(&:strip).reject(&:blank?)
    return shade_name_raw if candidates.size <= 1
    return candidates.first if description.blank?

    desc_tokens = tokenize_shade(description)
    return candidates.first if desc_tokens.empty?

    best = candidates.max_by do |candidate|
      c_tokens = tokenize_shade(candidate)
      [shade_score(c_tokens, desc_tokens), c_tokens.size]
    end

    shade_score(tokenize_shade(best), desc_tokens) > 0 ? best : candidates.first
  end

  # Fraction of candidate tokens that fuzzy-match at least one description token.
  # Tiebroken externally by candidate token count (more specific candidate wins).
  def shade_score(candidate_tokens, desc_tokens)
    return 0 if candidate_tokens.empty?
    matched = candidate_tokens.count { |ct| desc_tokens.any? { |dt| tokens_similar?(ct, dt) } }
    matched.to_f / candidate_tokens.size
  end

  # Normalise a shade name or product description into lowercase alpha tokens.
  # Splits camelCase so "OxBlue" becomes ["ox", "blue"].
  # Drops pure-number tokens and single-character tokens.
  def tokenize_shade(str)
    str.to_s
       .gsub(/([a-z])([A-Z])/, '\1 \2')
       .downcase
       .gsub(/[^a-z]+/, ' ')
       .split
       .reject { |t| t.length < 2 }
  end

  # Three-tier fuzzy match between two normalised tokens:
  #   1. Exact equality
  #   2. One is a full prefix of the other — handles abbreviations in both
  #      directions, e.g. "sm" ↔ "smoke", "ox" ↔ "oxblue"
  #   3. Levenshtein distance ≤ 1 (tokens ≥ 3 chars only) — handles truncated
  #      words like "gry" ↔ "grey", "blu" ↔ "blue"
  def tokens_similar?(a, b)
    return true if a == b
    return true if a.start_with?(b) || b.start_with?(a)
    a.length >= 3 && b.length >= 3 && levenshtein_distance(a, b) <= 1
  end

  # Space-efficient two-row Levenshtein implementation.
  def levenshtein_distance(a, b)
    return b.length if a.empty?
    return a.length if b.empty?

    prev = (0..b.length).to_a
    curr = Array.new(b.length + 1, 0)

    (1..a.length).each do |i|
      curr[0] = i
      (1..b.length).each do |j|
        curr[j] = if a[i - 1] == b[j - 1]
                    prev[j - 1]
                  else
                    1 + [prev[j], curr[j - 1], prev[j - 1]].min
                  end
      end
      prev, curr = curr, prev
    end

    prev[b.length]
  end

  # ── Log writer ──────────────────────────────────────────────────────────────

  def write_log(product:, rule:, status:, confidence:,
                row: nil, enriched: [], skipped: {}, details: {}, notes: nil)
    ApPriceListSyncLog.create!(
      product:              product,
      ap_price_list_row_id: row&.id,
      rule_applied:         rule,
      match_status:         status,
      confidence:           confidence,
      fields_enriched:      enriched,
      fields_skipped:       skipped,
      match_details:        details,
      notes:                notes,
      run_at:               @run_at,
      run_by_id:            @triggered_by_user_id
    )
  rescue => e
    Rails.logger.error "[ApPriceListSyncJob] log write failed for product ##{product.id}: #{e.message}"
  end

end
