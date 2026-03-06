# app/controllers/setup/products_controller.rb
class Setup::ProductsController < Setup::BaseController
  before_action :set_product, only: [:show, :edit, :update, :destroy]

  # GET /setup/products
  def index
    @products = Product.includes(:product_category, :base_uom, :brand).ordered

    @products = @products.for_category(params[:category_id]) if params[:category_id].present?
    @products = @products.for_brand(params[:brand_id])       if params[:brand_id].present?

    if params[:status].present?
      @products = params[:status] == 'active' ? @products.active : @products.inactive
    end

    @products = @products.limit(20)

    @selected_category = ProductCategory.find_by(id: params[:category_id])
    @categories        = ProductCategory.active.ordered
    @brands            = Brand.active.ordered
    @active_count      = Product.active.count
    @inactive_count    = Product.inactive.count
  end

  def show; end

  # GET /setup/products/export
  def export
    @products = Product.includes(:product_category, :base_uom, :brand).ordered

    package = Axlsx::Package.new
    wb      = package.workbook

    hdr  = wb.styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
             alignment: { horizontal: :center, vertical: :center })
    even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
             alignment: { horizontal: :right })

    wb.add_worksheet(name: 'Products') do |sheet|
      sheet.add_row(
        ['Category', 'UOM', 'Brand', 'Pack Code', 'Description',
         'Material Code', 'Product Code', 'HSN Code', 'GST Rate', 'MRP', 'Active'],
        style: hdr, height: 24
      )

      @products.each_with_index do |p, i|
        row_style = i.even? ? even : odd
        sheet.add_row([
          p.product_category&.name,
          p.base_uom&.short_name,
          p.brand&.name,
          p.pack_code,
          p.description,
          p.material_code,
          p.product_code,
          p.hsn_code,
          p.gst_rate,
          Product.column_names.include?('mrp') ? p.mrp : nil,
          p.active
        ], style: [row_style, row_style, row_style, row_style, row_style,
                   row_style, row_style, row_style, num, num, row_style],
           height: 18)
      end

      sheet.column_widths 22, 10, 18, 12, 34, 18, 18, 12, 10, 12, 8
    end

    send_data package.to_stream.read,
      filename:    "products_export_#{Date.today.strftime('%Y%m%d')}.xlsx",
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
    @categories = ProductCategory.active.ordered
    @uoms       = Uom.active.ordered
    @brands     = Brand.active.ordered
  end

  # PATCH /setup/products/:id
  def update
    if @product.update(product_params)
      redirect_to setup_product_path(@product), notice: 'Product updated successfully.'
    else
      @categories = ProductCategory.active.ordered
      @uoms       = Uom.active.ordered
      @brands     = Brand.active.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /setup/products/:id
  def destroy
    @product.destroy
    redirect_to setup_products_path, notice: 'Product deleted.'
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    allowed = %i[product_category_id base_uom_id brand_id
                 material_code product_code pack_code
                 description hsn_code gst_rate active]
    allowed << :mrp      if Product.column_names.include?('mrp')
    allowed << :metadata if Product.column_names.include?('metadata')
    params.require(:product).permit(*allowed)
  end

end