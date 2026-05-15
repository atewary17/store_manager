# app/controllers/setup/products_controller.rb
class Setup::ProductsController < Setup::BaseController
  before_action :set_product, only: [:show, :edit, :update, :destroy]

  PER_PAGE_OPTIONS = [25, 50, 75].freeze

  # GET /setup/products
  # Shows products enrolled in the current org's catalogue.
  # Superadmin with no org context falls back to the full master catalogue.
  def index
    base = @organisation ? Product.for_org(@organisation) : Product.all

    @products = base.includes(:product_category, :base_uom, :brand).order('products.id ASC')

    @products = @products.for_category(params[:category_id]) if params[:category_id].present?
    @products = @products.for_brand(params[:brand_id])       if params[:brand_id].present?

    if params[:status].present?
      @products = params[:status] == 'active' ? @products.active : @products.inactive
    end

    @per_page          = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
    @page              = [params[:page].to_i, 1].max
    @total_count       = @products.count
    @total_pages       = (@total_count.to_f / @per_page).ceil
    @page              = [@page, @total_pages].min if @total_pages > 0
    @products          = @products.offset((@page - 1) * @per_page).limit(@per_page)

    @selected_category = ProductCategory.find_by(id: params[:category_id])
    @categories        = ProductCategory.active.ordered
    @brands            = Brand.active.ordered
    @active_count      = base.active.count
    @inactive_count    = base.inactive.count
  end

  # GET /setup/product_register  (superadmin only)
  # Global register: all products in the master catalogue with org usage
  def product_register
    unless current_user.super_admin?
      redirect_to setup_products_path, alert: 'Access denied.'
      return
    end

    @products = Product.includes(:product_category, :base_uom, :brand,
                                  organisation_products: :organisation)
                       .ordered

    @products = @products.for_category(params[:category_id]) if params[:category_id].present?
    @products = @products.for_brand(params[:brand_id])       if params[:brand_id].present?

    if params[:status].present?
      @products = params[:status] == 'active' ? @products.active : @products.inactive
    end

    @selected_category  = ProductCategory.find_by(id: params[:category_id])
    @categories         = ProductCategory.active.ordered
    @brands             = Brand.active.ordered
    @orgs               = Organisation.order(:name)

    # Stats (unfiltered totals for header cards)
    @total_count      = Product.count
    @active_count     = Product.active.count
    @inactive_count   = Product.inactive.count
    @enrolled_count   = OrganisationProduct.select(:product_id).distinct.count
    @unenrolled_count = @total_count - @enrolled_count

    # Pagination on the filtered set
    @filtered_count = @products.count
    @per_page       = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
    @page           = [params[:page].to_i, 1].max
    @total_pages    = (@filtered_count.to_f / @per_page).ceil
    @page           = [@page, @total_pages].min if @total_pages > 0
    @products       = @products.offset((@page - 1) * @per_page).limit(@per_page)

    # AI-enriched pending products — for the "Unmatched" review tab
    @pending_products = Product
      .where(active: false)
      .where("metadata->>'source' = 'ai_enrichment'")
      .includes(:product_category, :base_uom, :brand, organisation_products: :organisation)
      .order('products.created_at DESC')
    @pending_count = @pending_products.count
  end

  def show
    @org_products = @product.organisation_products.includes(:organisation).order('organisations.name')
    @stock_levels = StockLevel.where(product_id: @product.id)
                              .joins("INNER JOIN organisations ON organisations.id = stock_levels.organisation_id")
                              .select('stock_levels.*, organisations.name AS org_name')
                              .order('organisations.name')

    # Origin tracing: load PI items that reference this product (unmatched origin)
    if @product.source == 'pi_scan' || @product.metadata&.dig('created_from_pi')
      @origin_items = PurchaseInvoiceItem
                        .where(product_id: @product.id)
                        .includes(purchase_invoice: [:user, :organisation, :supplier])
                        .order('purchase_invoice_items.created_at ASC')
                        .limit(10)
    end
  end

  # POST /setup/products/:id/approve
  # Super admin promotes an AI-enriched product to active
  def approve_pending
    unless current_user.super_admin?
      redirect_to product_register_setup_products_path, alert: 'Access denied.'
      return
    end
    @product = Product.find(params[:id])
    unless @product.metadata&.dig('source') == 'ai_enrichment'
      redirect_to product_register_setup_products_path, alert: 'Not an AI-enriched product.'
      return
    end
    @product.update!(
      active:   true,
      metadata: @product.metadata.merge(
        'validation_status' => 'approved',
        'approved_by'       => current_user.id,
        'approved_at'       => Time.current.iso8601
      )
    )
    redirect_to product_register_setup_products_path,
      notice: "#{@product.description} approved and is now active."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_setup_product_path(@product),
      alert: "Cannot approve — please complete the product first: #{e.record.errors.full_messages.join(', ')}"
  end

  # DELETE /setup/products/:id/reject_pending
  # Super admin rejects and deletes a pending AI-enriched product (only if no stock)
  def reject_pending
    unless current_user.super_admin?
      redirect_to product_register_setup_products_path, alert: 'Access denied.'
      return
    end
    @product = Product.find(params[:id])
    stock_qty = StockLevel.where(product_id: @product.id).sum(:quantity).to_f
    if stock_qty > 0
      redirect_to product_register_setup_products_path,
        alert: "Cannot delete — #{@product.description} has #{stock_qty} units in stock. Edit and approve instead."
      return
    end
    name = @product.description
    @product.destroy!
    redirect_to product_register_setup_products_path,
      notice: "#{name} removed from pending products."
  end

  # GET /setup/products/product_register_export  (superadmin only)
  # Exports ALL products globally with comma-separated organisation_ids column
  def product_register_export
    unless current_user.super_admin?
      redirect_to setup_products_path, alert: 'Access denied.'
      return
    end

    @products = Product.includes(:product_category, :base_uom, :brand,
                                  organisation_products: :organisation)
                       .order('products.id ASC')

    # Build map: product_id -> "org1,org2,org3"
    org_ids_map = OrganisationProduct
                    .select(:product_id, :organisation_id)
                    .group_by(&:product_id)
                    .transform_values { |ops| ops.map(&:organisation_id).join(',') }

    package = Axlsx::Package.new
    wb      = package.workbook

    hdr     = wb.styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
                alignment: { horizontal: :center, vertical: :center })
    even    = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd     = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num     = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
                alignment: { horizontal: :right })
    txt     = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
                format_code: '@')
    txt_even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10,
                 format_code: '@')

    meta_hdr  = wb.styles.add_style(bg_color: '2E4057', fg_color: 'FFFFFF', b: true, sz: 10,
                  alignment: { horizontal: :center, vertical: :center })
    meta_cell = wb.styles.add_style(bg_color: 'FAFBFC', fg_color: '666666', sz: 9,
                  format_code: '@')

    wb.add_worksheet(name: 'Product Register') do |sheet|
      sheet.add_row(
        ['Category', 'UOM', 'Brand', 'Pack Code', 'Shade Code', 'Description',
         'Material Code', 'Product Code', 'HSN Code', 'GST Rate',
         'Active', 'Organisation IDs',
         'meta:tint', 'meta:family_colour', 'meta:canister_volume_ml', 'meta:is_tinting_base',
         'meta:source', 'meta:validation_status', 'meta:ai_confidence',
         'meta:ai_brand_guess', 'meta:ai_category_guess', 'meta:ai_notes',
         'meta:original_name', 'meta:created_by_org'],
        style: [hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,
                meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,
                meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr],
        height: 24
      )

      @products.each_with_index do |p, i|
        row_style  = i.even? ? even : odd
        code_style = i.even? ? txt_even : txt
        meta       = p.metadata || {}

        sheet.add_row([
          p.product_category&.name,
          p.base_uom&.short_name,
          p.brand&.name,
          p.pack_code,
          p.shade_code.to_s,
          p.description,
          p.material_code.to_s,
          p.product_code.to_s,
          p.hsn_code.to_s,
          p.gst_rate,
          p.active,
          org_ids_map[p.id] || '',
          meta['tint'].to_s,
          meta['family_colour'].to_s,
          meta['canister_volume_ml'].to_s,
          meta['is_tinting_base'].to_s,
          meta['source'].to_s,
          meta['validation_status'].to_s,
          meta['ai_confidence'].to_s,
          meta['ai_brand_guess'].to_s,
          meta['ai_category_guess'].to_s,
          meta['ai_notes'].to_s,
          meta['original_name'].to_s,
          meta['created_by_org'].to_s
        ], style: [row_style, row_style, row_style, row_style, code_style, row_style,
                   code_style, code_style, code_style, num, row_style, row_style,
                   meta_cell, meta_cell, meta_cell, meta_cell,
                   meta_cell, meta_cell, meta_cell, meta_cell,
                   meta_cell, meta_cell, meta_cell, meta_cell],
           height: 18)
      end

      sheet.column_widths 22, 10, 18, 12, 14, 36, 20, 18, 12, 10, 8, 24,
                          12, 18, 18, 20, 14, 18, 14, 18, 18, 28, 28, 14
    end

    send_data package.to_stream.read,
      filename:    "product_register_#{Date.today.strftime('%Y%m%d')}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  # GET /setup/products/export
  # Exports products scoped to current org, including org-level overrides.
  # Used both as a data export and as a pre-filled import template.
  def export
    if @organisation
      # Org export: only products enrolled in this org (INNER JOIN)
      org_products = OrganisationProduct
                       .where(organisation_id: @organisation.id)
                       .includes(product: [:product_category, :base_uom, :brand])
                       .order('products.id ASC')
                       .joins(:product)

      @products       = org_products.map(&:product)
      org_product_map = org_products.index_by(&:product_id)
    else
      # Super admin with no org — export everything (no org overrides)
      @products       = Product.includes(:product_category, :base_uom, :brand).order('products.id ASC')
      org_product_map = {}
    end

    package = Axlsx::Package.new
    wb      = package.workbook

    hdr  = wb.styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
             alignment: { horizontal: :center, vertical: :center })
    even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
             alignment: { horizontal: :right })
    # Text format — forces Excel to treat codes as strings, preserving leading zeros
    txt  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
             format_code: '@')
    txt_even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10,
                 format_code: '@')

    # Extra metadata styles
    meta_hdr = wb.styles.add_style(bg_color: '2E4057', fg_color: 'FFFFFF', b: true, sz: 10,
                 alignment: { horizontal: :center, vertical: :center })
    meta_cell = wb.styles.add_style(bg_color: 'FAFBFC', fg_color: '666666', sz: 9,
                  format_code: '@')

    wb.add_worksheet(name: 'Products') do |sheet|
      # Row 1: Column headers
      sheet.add_row(
        ['Category', 'UOM', 'Brand', 'Pack Code', 'Shade Code', 'Description',
         'Material Code', 'Product Code', 'HSN Code', 'GST Rate',
         'MRP', 'Internal Code', 'Local Description', 'Active',
         # ── Metadata columns ──
         'meta:tint', 'meta:family_colour', 'meta:canister_volume_ml', 'meta:is_tinting_base',
         'meta:source', 'meta:validation_status', 'meta:ai_confidence',
         'meta:ai_brand_guess', 'meta:ai_category_guess', 'meta:ai_notes',
         'meta:original_name', 'meta:created_by_org'],
        style: [hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,hdr,
                meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr,
                meta_hdr,meta_hdr,meta_hdr,meta_hdr,meta_hdr],
        height: 24
      )

      @products.each_with_index do |p, i|
        op         = org_product_map[p.id]
        row_style  = i.even? ? even : odd
        code_style = i.even? ? txt_even : txt
        meta       = p.metadata || {}

        sheet.add_row([
          p.product_category&.name,
          p.base_uom&.short_name,
          p.brand&.name,
          p.pack_code,
          p.shade_code.to_s,
          p.description,
          p.material_code.to_s,
          p.product_code.to_s,
          p.hsn_code.to_s,
          p.gst_rate,
          op&.mrp,
          op&.internal_code,
          op&.local_description,
          p.active,
          # ── Metadata values ──
          meta['tint'].to_s,
          meta['family_colour'].to_s,
          meta['canister_volume_ml'].to_s,
          meta['is_tinting_base'].to_s,
          meta['source'].to_s,
          meta['validation_status'].to_s,
          meta['ai_confidence'].to_s,
          meta['ai_brand_guess'].to_s,
          meta['ai_category_guess'].to_s,
          meta['ai_notes'].to_s,
          meta['original_name'].to_s,
          meta['created_by_org'].to_s
        ], style: [row_style, row_style, row_style, row_style, code_style, row_style,
                   code_style, code_style, code_style, num, num,
                   row_style, row_style, row_style,
                   meta_cell, meta_cell, meta_cell, meta_cell,
                   meta_cell, meta_cell, meta_cell, meta_cell,
                   meta_cell, meta_cell, meta_cell, meta_cell],
           height: 18)
      end

      sheet.column_widths 22, 10, 18, 12, 14, 34, 18, 18, 12, 10, 12, 20, 30, 8,
                          12, 18, 18, 20, 14, 18, 14, 18, 18, 28, 28, 14
    end

    send_data package.to_stream.read,
      filename:    "products_#{@organisation&.name&.parameterize || 'all'}_#{Date.today.strftime('%Y%m%d')}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  # GET /setup/products/new
  def new
    @product    = Product.new(active: true, gst_rate: 18.0)
    @categories = ProductCategory.active.ordered
    @uoms       = Uom.active.ordered
    @brands     = Brand.active.ordered
  end

  # POST /setup/products
  def create
    @product = Product.new(product_params)
    if @product.save
      # Auto-enrol in current org's catalogue
      @product.enrol_in!(@organisation) if @organisation
      redirect_to setup_product_path(@product), notice: 'Product created successfully.'
    else
      @categories = ProductCategory.active.ordered
      @uoms       = Uom.active.ordered
      @brands     = Brand.active.ordered
      render :new, status: :unprocessable_entity
    end
  end

  # GET /setup/products/:id/edit
  def edit
    @categories           = ProductCategory.active.ordered
    @uoms                 = Uom.active.ordered
    @brands               = Brand.active.ordered
    # For superadmin: show org enrolment panel
    if current_user.super_admin?
      @all_orgs           = Organisation.order(:name)
      @enrolled_org_ids   = @product.organisation_products.pluck(:organisation_id)
    end
  end

  # PATCH /setup/products/:id
  def update
    if @product.update(product_params)
      # Superadmin can toggle org enrolments from the edit page
      if current_user.super_admin? && params[:enrol_org_ids]
        selected_ids = Array(params[:enrol_org_ids]).map(&:to_i).uniq
        # Enrol newly selected orgs
        selected_ids.each { |oid| OrganisationProduct.find_or_create_by!(organisation_id: oid, product_id: @product.id) }
        # Deactivate orgs that were unchecked (don't delete — preserve history)
        OrganisationProduct.where(product_id: @product.id)
                           .where.not(organisation_id: selected_ids)
                           .update_all(active: false)
        OrganisationProduct.where(product_id: @product.id, organisation_id: selected_ids)
                           .update_all(active: true)
      elsif @organisation
        # Regular admin: always keep enrolled in own org
        @product.enrol_in!(@organisation)
      end
      redirect_to setup_product_path(@product), notice: 'Product updated successfully.'
    else
      @categories         = ProductCategory.active.ordered
      @uoms               = Uom.active.ordered
      @brands             = Brand.active.ordered
      @all_orgs           = Organisation.order(:name) if current_user.super_admin?
      @enrolled_org_ids   = @product.organisation_products.pluck(:organisation_id) if current_user.super_admin?
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /setup/products/:id  (super_admin only)
  def destroy
    unless current_user.super_admin?
      redirect_to setup_products_path, alert: 'Only super admins can delete products.'
      return
    end
    @product.destroy
    redirect_to setup_products_path, notice: 'Product deleted.'
  end

  private

  def set_product
    @product = Product.includes(:reviewed_by, :merged_into).find(params[:id])
  end

  def product_params
    allowed = %i[product_category_id base_uom_id brand_id
                 material_code product_code pack_code shade_code
                 description hsn_code gst_rate active]
    allowed << :mrp if Product.column_names.include?('mrp')
    # Permit metadata as a hash with any keys (known fields + custom)
    if Product.column_names.include?('metadata')
      allowed << { metadata: {} }
    end
    p = params.require(:product).permit(*allowed,
          metadata_custom_keys:   [],
          metadata_custom_values: [])

    # Merge custom key-value pairs into metadata
    if p[:metadata_custom_keys].present?
      custom = {}
      p[:metadata_custom_keys].each_with_index do |k, i|
        key = k.to_s.strip
        val = p[:metadata_custom_values][i].to_s.strip
        custom[key] = val if key.present?
      end
      p[:metadata] = (p[:metadata] || {}).merge(custom)
    end

    p.except(:metadata_custom_keys, :metadata_custom_values)
  end

end