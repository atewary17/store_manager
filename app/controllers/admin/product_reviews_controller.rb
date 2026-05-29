# app/controllers/admin/product_reviews_controller.rb
class Admin::ProductReviewsController < Admin::BaseController

  before_action :set_product, only: [:show, :update, :approve, :reject, :merge]

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
