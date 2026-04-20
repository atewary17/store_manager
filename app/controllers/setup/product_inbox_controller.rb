class Setup::ProductInboxController < Setup::BaseController

  def index
    @items = ProductInboxItem.where(organisation: @organisation)
    @items = @items.where(status: params[:status]) if params[:status].present?
    @items = @items.where.not(status: %w[approved mapped ignored]) if params[:status].blank?
    @items = @items.includes(:purchase_invoice_item).order(created_at: :asc)

    @stats = {
      pending:        ProductInboxItem.where(organisation: @organisation, status: 'pending').count,
      ai_processing:  ProductInboxItem.where(organisation: @organisation, status: 'ai_processing').count,
      needs_review:   ProductInboxItem.where(organisation: @organisation, status: 'needs_review').count,
      resolved_today: ProductInboxItem.where(organisation: @organisation,
                        status: %w[approved mapped ignored])
                        .where('resolved_at >= ?', Date.today.beginning_of_day).count
    }
  end

  def approve
    item       = ProductInboxItem.find_by!(organisation: @organisation, id: params[:id])
    enrichment = item.ai_enrichment || {}

    brand    = Brand.find_by(name: params[:brand_name].presence || enrichment['brand_guess'])
    category = ProductCategory.find_by(
                 name: params[:category_name].presence || enrichment['category_guess']
               )

    product = Product.create!(
      description:      params[:description].presence || enrichment['description'],
      material_code:    params[:material_code].presence || enrichment['material_code'],
      hsn_code:         params[:hsn_code].presence || enrichment['hsn_code'],
      gst_rate:         (params[:gst_rate].presence || enrichment['gst_rate'] || 18).to_f,
      brand:            brand,
      product_category: category,
      active:           true,
      catalogue_status: 'approved',
      metadata:         { 'source' => 'product_inbox', 'inbox_item_id' => item.id }
    )

    OrganisationProduct.find_or_create_by!(organisation: @organisation, product: product)

    ProductAliasService.record(@organisation, item.raw_invoice_text, product,
                               source: 'admin', confidence: 1.0)

    item.update!(
      status:              'approved',
      resolved_product_id: product.id,
      resolved_by_id:      current_user.id,
      resolved_at:         Time.current
    )

    if item.purchase_invoice_item
      item.purchase_invoice_item.update!(
        product:          product,
        catalogue_status: 'matched',
        stock_held:       false
      )
    end

    redirect_to setup_product_inbox_index_path,
      notice: "#{product.description} added to catalogue."
  end

  def map
    item    = ProductInboxItem.find_by!(organisation: @organisation, id: params[:id])
    product = Product.for_org(@organisation).find(params[:product_id])

    ProductAliasService.record(@organisation, item.raw_invoice_text, product,
                               source: 'admin', confidence: 1.0)

    item.update!(
      status:              'mapped',
      resolved_product_id: product.id,
      resolved_by_id:      current_user.id,
      resolved_at:         Time.current
    )

    if item.purchase_invoice_item
      item.purchase_invoice_item.update!(
        product:          product,
        catalogue_status: 'matched',
        stock_held:       false
      )
    end

    redirect_to setup_product_inbox_index_path,
      notice: "Mapped to #{product.description}."
  end

  def ignore
    item = ProductInboxItem.find_by!(organisation: @organisation, id: params[:id])
    item.update!(
      status:         'ignored',
      resolved_by_id: current_user.id,
      resolved_at:    Time.current,
      ai_enrichment:  item.ai_enrichment.merge('ignore_note' => params[:note])
    )

    if item.purchase_invoice_item
      item.purchase_invoice_item.update!(
        catalogue_status: 'ignored',
        stock_held:       false
      )
    end

    redirect_to setup_product_inbox_index_path, notice: 'Item ignored.'
  end

end
