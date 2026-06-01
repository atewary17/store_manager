# app/controllers/admin/product_reviews_controller.rb
class Admin::ProductReviewsController < Admin::BaseController

  before_action :set_product, only: [:show, :update, :approve, :reject, :merge, :apply_suggestion]

  PER_PAGE = 25

  # GET /admin/product_reviews
  def index
    @total_pending = Product.review_pending.count
    @page          = [params[:page].to_i, 1].max
    @total_pages   = [(@total_pending.to_f / PER_PAGE).ceil, 1].max

    @products = Product.review_pending
                       .includes(:brand, :product_category, :base_uom,
                                 :organisation_products,
                                 purchase_invoice_items: :purchase_invoice)
                       .offset((@page - 1) * PER_PAGE)
                       .limit(PER_PAGE)
  end

  # GET /admin/product_reviews/:id
  def show
    @matches    = ProductSimilarityService.find_matches(@product, limit: 8)
    @pi_items   = @product.purchase_invoice_items
                          .includes(purchase_invoice: [:supplier, :organisation])
                          .order('purchase_invoices.created_at DESC')
    @org_names  = @product.organisation_products
                          .includes(:organisation)
                          .map { |op| op.organisation.name }
    @digitise_import = find_digitise_import
    @enrichment      = @product.internet_details&.dig('groq_enrichment')
    @enrichment_log  = ExternalApiLog
                         .where(service: 'groq', operation: 'product_enrichment')
                         .where("metadata->>'product_id' = ?", @product.id.to_s)
                         .order(created_at: :desc)
                         .first
    @brands     = Brand.ordered.pluck(:name, :id)
    @categories = ProductCategory.ordered.pluck(:name, :id)
    @uoms       = Uom.ordered.map { |u| [u.display, u.id] }
    @suggestion = ApPriceListSuggestionService.build(@product)
  end

  # PATCH /admin/product_reviews/:id
  def update
    if @product.update(product_params)
      redirect_to admin_product_review_path(@product), notice: 'Product details saved.'
    else
      redirect_to admin_product_review_path(@product),
                  alert: @product.errors.full_messages.join(', ')
    end
  end

  # POST /admin/product_reviews/:id/approve
  def approve
    @product.update!(
      active:           true,
      under_review:     false,
      catalogue_status: 'active',
      reviewed_at:      Time.current,
      reviewed_by:      current_user,
      review_notes:     params[:review_notes].presence
    )

    # Also mark all linked PI items as no longer unmatched
    @product.purchase_invoice_items.update_all(unmatched: false)

    begin
      ActivityLogger.log(
        organisation:     nil,
        user:             current_user,
        activity_type:    'product_approval',
        activity_subtype: 'approved',
        description:      "Product approved — #{@product.display_name}",
        reference:        @product,
        metadata:         { product_id: @product.id, material_code: @product.material_code }.compact
      )
    rescue => e
      Rails.logger.warn("[ActivityLog] product_approval approve #{@product.id}: #{e.message}")
    end

    redirect_to admin_product_reviews_path,
                notice: "#{@product.display_name} approved and activated."
  end

  # POST /admin/product_reviews/:id/reject
  def reject
    @product.update!(
      active:           false,
      under_review:     false,
      catalogue_status: 'rejected',
      reviewed_at:      Time.current,
      reviewed_by:      current_user,
      review_notes:     params[:review_notes].presence
    )

    begin
      ActivityLogger.log(
        organisation:     nil,
        user:             current_user,
        activity_type:    'product_approval',
        activity_subtype: 'rejected',
        description:      "Product rejected — #{@product.display_name}",
        reference:        @product,
        metadata:         { product_id: @product.id, material_code: @product.material_code }.compact
      )
    rescue => e
      Rails.logger.warn("[ActivityLog] product_approval reject #{@product.id}: #{e.message}")
    end

    redirect_to admin_product_reviews_path,
                notice: "#{@product.display_name} rejected."
  end

  # POST /admin/product_reviews/:id/merge
  def merge
    target = Product.find_by(id: params[:target_product_id])
    unless target
      return redirect_to admin_product_review_path(@product),
                         alert: 'Target product not found.'
    end

    result = ProductMergeService.call(
      under_review_product: @product,
      target_product:       target,
      performed_by:         current_user
    )

    if result[:success]
      redirect_to admin_product_reviews_path,
                  notice: "Merged into #{target.display_name}. All stock and invoice data transferred."
    else
      redirect_to admin_product_review_path(@product),
                  alert: "Merge failed: #{result[:error]}"
    end
  end

  # POST /admin/product_reviews/:id/apply_suggestion
  # Writes price-list-derived fields into the product's description + metadata.
  # Product stays under_review — admin must still approve manually.
  def apply_suggestion
    description       = params[:suggested_description].to_s.strip
    shade_name        = params[:shade_name].to_s.strip.presence
    product_line_desc = params[:product_line_desc].to_s.strip.presence
    pack_size_desc    = params[:pack_size_desc].to_s.strip.presence
    pack_size_litres  = params[:pack_size_litres].presence&.to_f
    dealer_price      = params[:dealer_price].presence&.to_d
    brand_id          = params[:brand_id].presence&.to_i
    category_name     = params[:category_name].to_s.strip.presence

    meta = @product.metadata.dup
    meta['product_line_desc'] = product_line_desc if product_line_desc
    meta['shade_name']        = shade_name        if shade_name
    meta['pack_size_desc']    = pack_size_desc     if pack_size_desc
    meta['pack_size_litres']  = pack_size_litres   if pack_size_litres
    meta['dealer_price']      = dealer_price       if dealer_price

    updates = {
      description: description.presence || @product.description,
      metadata:    meta
    }

    # Apply brand — only overwrite if currently blank or "Others"
    if brand_id.present?
      current_brand_name = @product.brand&.name&.downcase
      updates[:brand_id] = brand_id if current_brand_name.blank? || current_brand_name == 'others'
    end

    # Apply category — look up by name, only overwrite if currently "Others"
    if category_name.present?
      current_cat_name = @product.product_category&.name&.downcase
      if current_cat_name.blank? || current_cat_name == 'others'
        cat = ProductCategory.find_by('LOWER(name) = ?', category_name.downcase)
        updates[:product_category_id] = cat.id if cat
      end
    end

    @product.update!(updates)

    redirect_to admin_product_review_path(@product),
                notice: 'Suggestion applied — description, brand, and category updated. Review and approve when ready.'
  rescue => e
    redirect_to admin_product_review_path(@product),
                alert: "Could not apply suggestion: #{e.message}"
  end

  private

  def set_product
    @product = Product.find(params[:id])
    redirect_to admin_product_reviews_path, alert: 'Product not found.' unless @product
  end

  def product_params
    params.require(:product).permit(
      :description, :material_code, :brand_id,
      :product_category_id, :base_uom_id, :hsn_code, :gst_rate
    )
  end

  def find_digitise_import
    pi_ids = @product.purchase_invoice_items.pluck(:purchase_invoice_id).uniq
    return nil if pi_ids.empty?

    DigitiseImport.where(purchase_invoice_id: pi_ids)
                  .order(created_at: :desc)
                  .first
  end

end
