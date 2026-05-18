# app/jobs/ap_price_list_sync_job.rb
#
# Enriches existing Asian Paints products from staged price list rows.
# Never creates products. Never touches product.description.
#
# Rule 1  — Three-field exact match on product columns        (confidence: highest)
# Rule 2A — Decoded material code, full 3-field row match     (confidence: high)
# Rule 2B — Decoded material code, independent sub-queries    (confidence: medium / low_medium)
# NMPL    — No Match with Price List                          (confidence: none)
#
# Stops at the first rule that returns a result.
# One ApPriceListSyncLog entry is written per product per run.
# Products with metadata price_list_match_status of 'matched' or 'partial' are skipped.

class ApPriceListSyncJob < ApplicationJob
  queue_as :enrichment

  retry_on StandardError, wait: 5.minutes, attempts: 2

  AP_PACK_CODES = JSON.parse(
    File.read(Rails.root.join('config/asian_paints_pack_codes.json'))
  ).freeze

  def perform(import_batch_id: nil, triggered_by_user_id: nil)
    @triggered_by_user_id = triggered_by_user_id
    @run_at               = Time.current

    products = load_ap_products
    Rails.logger.info "[ApPriceListSyncJob] Starting — #{products.size} AP products to process"

    products.each do |product|
      process_product(product, import_batch_id)
    rescue => e
      Rails.logger.error "[ApPriceListSyncJob] product ##{product.id} failed: #{e.message}"
      write_log(product: product, rule: 'NMPL', status: 'nmpl',
                confidence: 'none', notes: "Unexpected error: #{e.message}")
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
      write_log(product: product, rule: 'SKIP', status: 'already_matched',
                confidence: 'none',
                notes: "Skipped — prior run status: #{product.metadata&.dig('price_list_match_status')}")
      return
    end

    @row_scope = scoped_rows(import_batch_id)

    result = run_rule1(product) ||
             run_rule2a(product) ||
             run_rule2b(product) ||
             run_nmpl(product)

    if result == :save_failed
      2.times do |attempt|
        break unless result == :save_failed
        sleep(0.5 * (attempt + 1))
        product.reload
        result = run_rule1(product) ||
                 run_rule2a(product) ||
                 run_rule2b(product) ||
                 run_nmpl(product)
      end
    end

    result
  end

  def already_matched?(product)
    product.metadata&.dig('price_list_match_status') == 'matched'
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
      latest = PriceListRow.where('effective_date <= ?', Date.today).maximum(:effective_date)
      latest ? PriceListRow.where(effective_date: latest) : PriceListRow.none
    end
  end

  # ── Rule 1: Three-field exact match on product columns ────────────────────
  # Requires product_code, pack_code, shade_code all present on the product.
  # Confidence: highest — direct column match, most reliable path.

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

    enriched, skipped, saved = enrich_from_row(product, row, rule: '1', confidence: 'highest')
    mark_row_matched(row, product) if saved
    write_log(
      product:    product,
      row:        row,
      rule:       '1',
      status:     saved ? 'matched' : 'save_failed',
      confidence: 'highest',
      enriched:   enriched,
      skipped:    skipped,
      details:    { prod_code: product.product_code,
                    pack_code: product.pack_code,
                    shade_code: product.shade_code },
      notes:      case_note
    )
    saved ? :matched : :save_failed
  end

  # ── Rule 2A: Decoded material code — full 3-field row match ───────────────
  # Cascades: shade_code → prod_code → pack_code in a single price list row.
  # Confidence: high — all three decoded components confirmed in one row.

  def run_rule2a(product)
    return nil unless valid_material_code?(product)

    dp, ds, dk = decode_material_code(product.material_code)

    row = @row_scope
            .where(shade_code: ds)
            .where(prod_code:  dp)
            .where(pack_code:  dk)
            .order(effective_date: :desc)
            .first

    return nil if row.nil?

    enriched, skipped, saved = enrich_from_row(product, row, rule: '2A', confidence: 'high',
                                                decoded: { dp: dp, ds: ds, dk: dk })
    mark_row_matched(row, product) if saved
    write_log(
      product:    product,
      row:        row,
      rule:       '2A',
      status:     saved ? 'matched' : 'save_failed',
      confidence: 'high',
      enriched:   enriched,
      skipped:    skipped,
      details:    { decoded_product_code: dp, decoded_shade_code: ds,
                    decoded_pack_code: dk, material_code: product.material_code }
    )
    saved ? :matched : :save_failed
  end

  # ── Rule 2B: Decoded material code — independent sub-queries ─────────────
  # Each decoded component (prod_code, shade_code, pack_code) is looked up
  # independently. Confidence depends on how many find a price list row.
  # No pricing fields synced here — 2A handles those when available.

  def run_rule2b(product)
    return nil unless valid_material_code?(product)

    dp, ds, dk = decode_material_code(product.material_code)

    enriched = []
    skipped  = {}
    meta     = product.metadata.dup

    # Step A — product_line_desc from prod_code match
    row_a = @row_scope.where(prod_code: dp)
                      .where.not(product_base_name: [nil, ''])
                      .order(effective_date: :desc).first
    if row_a
      meta['product_line_desc'] = row_a.product_base_name
      enriched << 'product_line_desc'
      if product.product_code.blank?
        if Product.where(product_code: dp).where.not(id: product.id).exists?
          skipped['product_code'] = "conflict — '#{dp}' already assigned to another product"
        else
          product.product_code = dp
          enriched << 'product_code'
        end
      end
    end

    # Step B — shade_name from shade_code match (with fuzzy disambiguation)
    row_b = @row_scope.where(shade_code: ds)
                      .where.not(shade_name: [nil, ''])
                      .order(effective_date: :desc).first
    if row_b
      resolved_shade, shade_conf  = resolve_shade_name_with_confidence(row_b.shade_name, product.description)
      meta['shade_name']           = resolved_shade
      meta['shade_match_confidence'] = shade_conf
      meta['is_tinting_base']      = tinting_base_shade?(resolved_shade)
      enriched << 'shade_name'
      enriched << 'is_tinting_base'
      if product.shade_code.blank?
        product.shade_code = ds
        enriched << 'shade_code'
      end
    end

    # Step C — pack_size from AP pack code lookup table
    pack_info = AP_PACK_CODES[dk]
    if pack_info
      meta['pack_size_litres']    = pack_info['pack_size_litres']
      meta['pack_size_desc']      = pack_info['pack_size_desc']
      meta['is_tinting_base']   ||= pack_info['is_tinting_base']
      meta['tinting_base_group']  = pack_info['tinting_base_group'] if pack_info['tinting_base_group']
      enriched << 'pack_size_litres'
      enriched << 'pack_size_desc'
      product.pack_code = dk if product.pack_code.blank?
    end

    matched_steps = [row_a.present?, row_b.present?, pack_info.present?].count(true)
    return nil if matched_steps == 0

    confidence = matched_steps >= 2 ? 'medium' : 'low_medium'
    best_row   = row_a || row_b

    meta['enriched_description'] = build_enriched_description(product, meta)
    meta.merge!(price_list_audit_fields(rule: '2B', confidence: confidence,
                                        status: 'partial', row: best_row))
    product.metadata = meta
    saved = save_product(product, skipped)

    write_log(
      product:    product,
      row:        best_row,
      rule:       '2B',
      status:     saved ? 'partial' : 'save_failed',
      confidence: confidence,
      enriched:   enriched,
      skipped:    skipped,
      details:    { decoded_product_code: dp, decoded_shade_code: ds,
                    decoded_pack_code: dk, material_code: product.material_code,
                    steps_matched: matched_steps,
                    step_a: row_a.present?, step_b: row_b.present?, step_c: pack_info.present? }
    )
    saved ? :partial : :save_failed
  end

  # ── NMPL: No Match with Price List ────────────────────────────────────────

  def run_nmpl(product)
    write_log(
      product:    product,
      rule:       'NMPL',
      status:     'nmpl',
      confidence: 'none',
      details:    { material_code: product.material_code,
                    product_code:  product.product_code,
                    pack_code:     product.pack_code,
                    shade_code:    product.shade_code },
      notes:      build_nmpl_note(product)
    )
    :nmpl
  end

  def build_nmpl_note(product)
    reasons = []

    unless product.product_code.present? && product.pack_code.present? && product.shade_code.present?
      reasons << "Rule 1 skipped: product_code/pack_code/shade_code not all present on product"
    end

    if product.material_code.blank?
      reasons << "Rules 2A/2B skipped: no material_code"
    elsif !product.material_code.match?(/\A[A-Z0-9]{11}\z/i)
      reasons << "Rules 2A/2B skipped: material_code '#{product.material_code}' is not 11 alphanumeric characters"
    else
      dp, ds, dk = decode_material_code(product.material_code)
      reasons << "Rules 2A/2B: no price list rows found for decoded codes " \
                 "(prod_code=#{dp}, shade_code=#{ds}, pack_code=#{dk})"
    end

    reasons.join(' | ')
  end

  # ── Shared enrichment — used by Rule 1 and Rule 2A ───────────────────────
  # Both have a single confirmed row with all fields available.

  def enrich_from_row(product, row, rule:, confidence:, decoded: nil)
    enriched = []
    skipped  = {}
    meta     = product.metadata.dup

    if row.product_base_name.present?
      meta['product_line_desc'] = row.product_base_name
      enriched << 'product_line_desc'
    end

    if row.shade_name.present?
      resolved_shade, shade_conf    = resolve_shade_name_with_confidence(row.shade_name, product.description)
      meta['shade_name']             = resolved_shade
      meta['shade_match_confidence'] = shade_conf
      meta['is_tinting_base']        = tinting_base_shade?(resolved_shade)
      enriched << 'shade_name'
      enriched << 'is_tinting_base'
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

    if row.dealer_price.present?
      meta['dealer_price']    = row.dealer_price
      meta['price_effective'] = row.effective_date&.iso8601
      enriched << 'dealer_price'
      enriched << 'price_effective'
    end

    # Column fields — only overwrite if blank
    dp = decoded&.dig(:dp)
    ds = decoded&.dig(:ds)
    dk = decoded&.dig(:dk)

    if product.product_code.blank?
      src = dp || row.prod_code
      if src.present?
        if Product.where(product_code: src).where.not(id: product.id).exists?
          skipped['product_code'] = "conflict — '#{src}' already assigned to another product"
        else
          product.product_code = src
          enriched << 'product_code'
        end
      end
    end

    product.shade_code = (ds || row.shade_code) if product.shade_code.blank? && (ds || row.shade_code).present?
    product.pack_code  = (dk || row.pack_code)  if product.pack_code.blank?  && (dk || row.pack_code).present?

    meta['enriched_description'] = build_enriched_description(product, meta)
    meta.merge!(price_list_audit_fields(rule: rule, confidence: confidence,
                                        status: 'matched', row: row))
    product.metadata = meta
    saved = save_product(product, skipped)

    [enriched, skipped, saved]
  end

  # ── Enriched description ──────────────────────────────────────────────────

  def build_enriched_description(product, meta)
    parts = [
      product.brand&.name,
      meta['product_line_desc'].presence,
      meta['shade_name'].presence,
      meta['pack_size_desc'].presence
    ].compact_blank
    parts.any? ? parts.join(' — ') : nil
  end

  # ── Audit fields stored in metadata ──────────────────────────────────────

  def price_list_audit_fields(rule:, confidence:, status:, row:)
    {
      'price_list_match_rule'       => rule,
      'price_list_match_confidence' => confidence,
      'price_list_match_status'     => status,
      'price_list_matched_at'       => @run_at.iso8601,
      'price_list_row_id'           => row&.id
    }
  end

  # ── Save helpers ──────────────────────────────────────────────────────────

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

  # ── Material code helpers ─────────────────────────────────────────────────

  def valid_material_code?(product)
    product.material_code.present? && product.material_code.match?(/\A[A-Z0-9]{11}\z/i)
  end

  def decode_material_code(material_code)
    [material_code[0..3], material_code[4..7], material_code[8..10]]
  end

  # ── Format helpers ────────────────────────────────────────────────────────

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

  def tinting_base_shade?(shade_name)
    return false if shade_name.blank?
    shade_name.to_s.match?(/tint(ing)?\s*base|\bTB\b|T\.B\./i)
  end

  # ── Shade name disambiguation ─────────────────────────────────────────────
  # Returns [resolved_name, confidence_level].
  # When shade_name is comma-separated, picks the candidate that best matches
  # the product description via token-level fuzzy scoring.

  def resolve_shade_name_with_confidence(shade_name_raw, description)
    return [shade_name_raw, 'single'] if shade_name_raw.blank?

    candidates = shade_name_raw.split(',').map(&:strip).reject(&:blank?)
    return [shade_name_raw, 'single'] if candidates.size <= 1

    if description.blank?
      return [candidates.first, 'fallback']
    end

    desc_tokens = tokenize_shade(description)
    if desc_tokens.empty?
      return [candidates.first, 'fallback']
    end

    best = candidates.max_by do |candidate|
      c_tokens = tokenize_shade(candidate)
      [shade_score(c_tokens, desc_tokens), c_tokens.size]
    end

    score = shade_score(tokenize_shade(best), desc_tokens)

    confidence = if score >= 1.0
                   'high'
                 elsif score >= 0.5
                   'medium'
                 elsif score > 0
                   'low'
                 else
                   'fallback'
                 end

    resolved = score > 0 ? best : candidates.first
    [resolved, confidence]
  end

  def shade_score(candidate_tokens, desc_tokens)
    return 0 if candidate_tokens.empty?
    matched = candidate_tokens.count { |ct| desc_tokens.any? { |dt| tokens_similar?(ct, dt) } }
    matched.to_f / candidate_tokens.size
  end

  # Normalises a shade name or product description into lowercase alpha tokens.
  # Splits camelCase ("OxBlue" → ["ox", "blue"]).
  # Drops single-character tokens.
  def tokenize_shade(str)
    str.to_s
       .gsub(/([a-z])([A-Z])/, '\1 \2')
       .downcase
       .gsub(/[^a-z]+/, ' ')
       .split
       .reject { |t| t.length < 2 }
  end

  # Four-tier fuzzy match:
  #   1. Exact equality
  #   2. Prefix match — handles abbreviations ("ox" ↔ "oxblue", "blu" ↔ "blue")
  #   3. Levenshtein ≤ 1 (tokens ≥ 3 chars) — handles truncations ("gry" ↔ "grey")
  #   4. Substring inclusion (min 5 chars) — handles AP concat codes (e.g. "dp-orange" token contains "orange")
  def tokens_similar?(a, b)
    return true if a == b
    return true if a.start_with?(b) || b.start_with?(a)
    return true if a.length >= 3 && b.length >= 3 && levenshtein_distance(a, b) <= 1
    (a.length >= 5 || b.length >= 5) && (a.include?(b) || b.include?(a))
  end

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

  # ── Log writer ────────────────────────────────────────────────────────────

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
