class InvoiceProductResolver

  ResolverResult = Struct.new(
    :product,         # Product or nil
    :match_gate,      # :exact | :fuzzy | :alias | :hsn | :ai_pending | :none
    :inbox_item,      # ProductInboxItem or nil
    :stock_immediate, # boolean — true = update stock now
    :confidence,      # float 0..1
    keyword_init: true
  )

  def self.resolve(organisation:, raw_text:, material_code: nil, hsn_code: nil,
                   supplier: nil, purchase_invoice_item: nil)
    new(
      organisation:           organisation,
      raw_text:               raw_text,
      material_code:          material_code,
      hsn_code:               hsn_code,
      supplier:               supplier,
      purchase_invoice_item:  purchase_invoice_item
    ).resolve
  end

  def initialize(organisation:, raw_text:, material_code:, hsn_code:,
                 supplier:, purchase_invoice_item:)
    @organisation          = organisation
    @raw_text              = raw_text.to_s.strip
    @material_code         = material_code.to_s.strip.presence
    @hsn_code              = hsn_code.to_s.strip.presence
    @supplier              = supplier
    @purchase_invoice_item = purchase_invoice_item
  end

  def resolve
    gate1_exact     ||
      gate2_fuzzy   ||
      gate3_alias   ||
      gate4_hsn     ||
      gate5_ai
  end

  private

  # ── Gate 1: exact material_code ──────────────────────────────────────────
  def gate1_exact
    return nil if @material_code.blank?

    product = Product.for_org(@organisation)
                     .where(active: true, catalogue_status: 'approved')
                     .where('LOWER(TRIM(material_code)) = LOWER(?)', @material_code)
                     .first
    return nil unless product

    ProductAliasService.record(@organisation, @raw_text, product,
                               source: 'exact', confidence: 1.0)

    ResolverResult.new(
      product:         product,
      match_gate:      :exact,
      inbox_item:      nil,
      stock_immediate: true,
      confidence:      1.0
    )
  end

  # ── Gate 2: pg_trgm fuzzy description ────────────────────────────────────
  def gate2_fuzzy
    return nil if @raw_text.length < 4

    quoted = Product.connection.quote(@raw_text)

    results = Product.for_org(@organisation)
                     .where(active: true, catalogue_status: 'approved')
                     .where('similarity(LOWER(products.description), LOWER(?)) > 0.4', @raw_text)
                     .select("products.*, similarity(LOWER(products.description), LOWER(#{quoted})) AS trgm_score")
                     .order('trgm_score DESC')
                     .limit(1)

    return nil if results.empty?

    product = results.first
    score   = product.try(:trgm_score).to_f
    return nil unless score > 0.4

    ProductAliasService.record(@organisation, @raw_text, product,
                               source: 'fuzzy', confidence: score)

    ResolverResult.new(
      product:         product,
      match_gate:      :fuzzy,
      inbox_item:      nil,
      stock_immediate: true,
      confidence:      score
    )
  rescue ActiveRecord::StatementInvalid
    nil
  end

  # ── Gate 3: alias table ───────────────────────────────────────────────────
  def gate3_alias
    product = ProductAliasService.lookup(@organisation, @raw_text,
                                         supplier_id: @supplier&.id)
    return nil unless product

    ResolverResult.new(
      product:         product,
      match_gate:      :alias,
      inbox_item:      nil,
      stock_immediate: true,
      confidence:      1.0
    )
  end

  # ── Gate 4: HSN code match ────────────────────────────────────────────────
  def gate4_hsn
    return nil if @hsn_code.blank? || @hsn_code.length < 4

    product = Product.for_org(@organisation)
                     .where(active: true, catalogue_status: 'approved')
                     .where(hsn_code: @hsn_code)
                     .first
    return nil unless product

    ProductAliasService.record(@organisation, @raw_text, product,
                               source: 'hsn', confidence: 0.7)

    ResolverResult.new(
      product:         product,
      match_gate:      :hsn,
      inbox_item:      nil,
      stock_immediate: true,
      confidence:      0.7
    )
  end

  # ── Gate 5: AI inbox (async, last resort) ─────────────────────────────────
  def gate5_ai
    inbox_item = ProductInboxItem.create!(
      organisation:          @organisation,
      raw_invoice_text:      @raw_text,
      material_code_hint:    @material_code,
      hsn_code_hint:         @hsn_code,
      supplier_name_hint:    @supplier&.name,
      purchase_invoice_item: @purchase_invoice_item,
      status:                ENV['GROQ_API_KEY'].present? ? 'ai_processing' : 'pending'
    )

    ProductClassifierJob.perform_later(inbox_item.id) if ENV['GROQ_API_KEY'].present?

    ResolverResult.new(
      product:         nil,
      match_gate:      :ai_pending,
      inbox_item:      inbox_item,
      stock_immediate: false,
      confidence:      0.0
    )
  end

end
