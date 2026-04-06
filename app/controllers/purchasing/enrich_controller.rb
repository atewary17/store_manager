# app/controllers/purchasing/enrich_controller.rb
#
# Handles async product enrichment requests from the invoice item form.
# Called via JS fetch() — MUST always return JSON, never HTML redirects.

class Purchasing::EnrichController < Purchasing::BaseController

  # Override base controller redirects — fetch() can't follow HTML redirects
  # If auth fails or org missing, return JSON error (not HTML sign-in page)
  rescue_from StandardError do |e|
    Rails.logger.error "[EnrichController] Unhandled error: #{e.class} — #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: { success: false, error: "Server error: #{e.message}" },
           status: :internal_server_error
  end

  before_action :ensure_json_auth
  before_action :ensure_json_org

  # POST /purchasing/enrich_product
  def enrich_product
    name          = params[:name].to_s.strip
    material_code = params[:material_code_hint].to_s.strip.presence
    brand_hint    = params[:brand_hint].to_s.strip.presence

    # ── Log incoming request ──
    Rails.logger.info "[EnrichController] enrich_product request"
    Rails.logger.info "[EnrichController]   name:          #{name.inspect}"
    Rails.logger.info "[EnrichController]   material_code: #{material_code.inspect}"
    Rails.logger.info "[EnrichController]   brand_hint:    #{brand_hint.inspect}"
    Rails.logger.info "[EnrichController]   user:          #{current_user.email}"
    Rails.logger.info "[EnrichController]   org:           #{@organisation.name}"

    if name.blank?
      Rails.logger.warn "[EnrichController] Rejected — name is blank"
      return render json: { success: false, error: 'Product name is required' },
                    status: :unprocessable_entity
    end

    Rails.logger.info "[EnrichController] Calling ProductEnrichmentService (Groq)..."

    result = ProductEnrichmentService.call(
      name:          name,
      material_code: material_code,
      brand_hint:    brand_hint
    )

    # ── Log response ──
    if result[:success]
      Rails.logger.info "[EnrichController] Enrichment SUCCESS"
      Rails.logger.info "[EnrichController]   description:   #{result.dig(:data, 'description')}"
      Rails.logger.info "[EnrichController]   material_code: #{result.dig(:data, 'material_code')}"
      Rails.logger.info "[EnrichController]   confidence:    #{result.dig(:data, 'confidence')}"
    else
      Rails.logger.warn "[EnrichController] Enrichment FAILED: #{result[:error]}"
    end

    if result[:success]
      data = result[:data]
      render json: {
        success:           true,
        data:              data,
        images_url:        google_images_url(name, material_code, brand_hint),
        confidence_label:  confidence_label(data['confidence'].to_f)
      }
    else
      render json: {
        success:    false,
        error:      result[:error] || 'Enrichment failed',
        images_url: google_images_url(name, material_code, brand_hint)
      }
    end
  end

  # POST /purchasing/save_enriched_product
  def save_enriched_product
    action_taken = params[:action_taken]

    Rails.logger.info "[EnrichController] save_enriched_product — action: #{action_taken}"
    Rails.logger.info "[EnrichController]   description:   #{params[:description].inspect}"
    Rails.logger.info "[EnrichController]   material_code: #{params[:material_code].inspect}"

    # Check for existing product first — avoid duplicates
    existing = find_existing(params[:material_code].to_s.strip.presence,
                             params[:original_name])
    if existing
      existing.enrol_in!(@organisation)
      Rails.logger.info "[EnrichController] Linked to existing product ##{existing.id}"
      render json: {
        success:    true,
        product_id: existing.id,
        created:    false,
        message:    "Linked to existing product: #{existing.description}"
      }
      return
    end

    # Resolve brand, category, UOM — returns error if not found in master data
    resolution = resolve_product_attrs(params)

    if resolution[:error]
      Rails.logger.warn "[EnrichController] Cannot save product — #{resolution[:error]}"
      render json: { success: false, error: resolution[:error] }
      return
    end

    product          = Product.new(resolution[:attrs])
    product.active   = false
    product.metadata = build_metadata(params, action_taken)

    if product.save
      product.enrol_in!(@organisation)
      Rails.logger.info "[EnrichController] Created pending product ##{product.id}: #{product.description}"
      render json: {
        success:    true,
        product_id: product.id,
        created:    true,
        message:    action_taken == 'confirm' ?
          'Product saved — pending admin review.' :
          'Product saved — flagged for manual validation.'
      }
    else
      Rails.logger.warn "[EnrichController] Product save failed: #{product.errors.full_messages}"
      render json: {
        success: false,
        error:   product.errors.full_messages.join(', ')
      }, status: :unprocessable_entity
    end
  end

  private

  # ── JSON-safe auth — returns JSON error instead of HTML redirect ──
  def ensure_json_auth
    return if user_signed_in?
    Rails.logger.warn "[EnrichController] Unauthenticated request — session may have expired"
    render json: { success: false, error: 'Session expired — please refresh the page and sign in again.' },
           status: :unauthorized
  end

  # ── JSON-safe org check ──
  def ensure_json_org
    return if @organisation.present?
    Rails.logger.warn "[EnrichController] No organisation found for user #{current_user.id}"
    render json: { success: false, error: 'No organisation context found.' },
           status: :unprocessable_entity
  end

  # Looks up brand, category and UOM from existing master data.
  # Returns either { attrs: {...} } on success
  # or { error: "message" } if brand/category cannot be resolved.
  def resolve_product_attrs(p)
    gst = p[:gst_rate].to_f
    gst = 18.0 unless [0, 5, 12, 18, 28].include?(gst.to_i)

    # ── Brand lookup ──────────────────────────────────────────
    brand_guess = p[:brand_guess].to_s.strip
    brand = nil
    if brand_guess.present?
      # Try progressively looser matches:
      # 1. Exact match
      # 2. Name contains the guess (e.g. "Asian Paints" contains "Asian")
      # 3. Name starts with first 3 chars (e.g. "AP" → "APCO" won't match "Asian Paints")
      brand = Brand.where('LOWER(name) = LOWER(?)', brand_guess).first ||
              Brand.where('LOWER(name) LIKE ?', "%#{brand_guess.downcase}%").first
    end

    if brand.nil?
      available = Brand.active.ordered.pluck(:name).first(10).join(', ')
      return {
        error: "Brand '#{brand_guess.presence || '(not provided)'}' was not found in your brand list. "                "Available brands: #{available}. "                "Please add the brand in Setup → Master Data → Brands first, then try again."
      }
    end

    # ── Category lookup ───────────────────────────────────────
    category_guess = p[:category_guess].to_s.strip
    category = nil
    if category_guess.present?
      category = ProductCategory.where('LOWER(name) = LOWER(?)', category_guess).first ||
                 ProductCategory.where('LOWER(name) LIKE ?', "%#{category_guess.downcase}%").first
    end

    if category.nil?
      available = ProductCategory.active.ordered.pluck(:name).first(10).join(', ')
      return {
        error: "Category '#{category_guess.presence || '(not provided)'}' was not found in your category list. "                "Available categories: #{available}. "                "Please add the category in Setup → Master Data → Product Categories first, then try again."
      }
    end

    # ── UOM lookup (with smart fallback based on pack size) ───
    pack = p[:pack_size_guess].to_s.downcase
    uom = if pack.match?(/\d+\s*(ml|l|ltr|litre)/i)
      Uom.where('LOWER(short_name) IN (?)', %w[ltr litre l]).first
    elsif pack.match?(/\d+\s*(kg|kgs|g|gram)/i)
      Uom.where('LOWER(short_name) IN (?)', %w[kg kgs gram g]).first
    elsif pack.match?(/\d+\s*(pc|pcs|nos|no)/i)
      Uom.where('LOWER(short_name) IN (?)', %w[pcs nos pc no]).first
    end
    uom ||= Uom.first  # safe fallback — UOM list always has at least one entry

    {
      attrs: {
        description:      p[:description].to_s.strip.presence || p[:original_name].to_s.strip,
        material_code:    p[:material_code].to_s.strip.presence,
        product_code:     p[:product_code].to_s.strip.presence,
        hsn_code:         p[:hsn_code].to_s.strip.presence,
        gst_rate:         gst,
        pack_code:        p[:pack_size_guess].to_s.strip.presence,
        product_category: category,
        brand:            brand,
        base_uom:         uom
      }
    }
  end

  # Keep old name as alias for any existing call sites
  def build_product_attrs(p)
    result = resolve_product_attrs(p)
    result[:attrs] || {}
  end

  def build_metadata(p, action)
    {
      'source'             => 'ai_enrichment',
      'validation_status'  => action == 'confirm' ? 'pending' : 'needs_validation',
      'original_name'      => p[:original_name].to_s.strip,
      'ai_confidence'      => p[:confidence].to_f,
      # Store all AI guesses for admin reference in Product Register review
      'ai_category_guess'  => p[:category_guess].to_s.strip.presence,
      'ai_brand_guess'     => p[:brand_guess].to_s.strip.presence,
      'ai_pack_size_guess' => p[:pack_size_guess].to_s.strip.presence,
      'ai_hsn_code'        => p[:hsn_code].to_s.strip.presence,
      'ai_gst_rate'        => p[:gst_rate].to_s.strip.presence,
      'ai_notes'           => p[:ai_notes].to_s.strip.presence,
      'needs_review'       => %w[brand product_category].select { |f|
                                # Flag which fields the admin still needs to fill in
                                case f
                                when 'brand'            then Brand.where('LOWER(name) LIKE ?', "%#{p[:brand_guess].to_s.downcase}%").none?
                                when 'product_category' then ProductCategory.where('LOWER(name) LIKE ?', "%#{p[:category_guess].to_s.downcase}%").none?
                                end
                              },
      'created_at'         => Time.current.iso8601,
      'created_by_org'     => @organisation.id
    }.compact
  end

  def find_existing(material_code, original_name)
    return nil if material_code.blank? && original_name.blank?

    if material_code.present?
      p = Product.find_by('LOWER(TRIM(material_code)) = LOWER(?)', material_code.strip)
      return p if p
    end
    nil
  rescue
    nil
  end

  def google_images_url(name, code, brand)
    query = [brand, name, code].compact_blank.join(' ')
    "https://www.google.com/search?q=#{CGI.escape(query)}&tbm=isch"
  end

  def confidence_label(score)
    case score
    when 0.8..1.0 then 'High confidence'
    when 0.5...0.8 then 'Medium confidence'
    else 'Low confidence — verify carefully'
    end
  end

end