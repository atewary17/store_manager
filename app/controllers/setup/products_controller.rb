# app/controllers/setup/products_controller.rb
class Setup::ProductsController < Setup::BaseController
  before_action :set_product, only: [:show, :edit, :update, :destroy]

  def index
    @products = Product.includes(:product_category, :base_uom).ordered

    # Filter by category if param present
    if params[:category_id].present?
      @products = @products.where(product_category_id: params[:category_id])
      @selected_category = ProductCategory.find_by(id: params[:category_id])
    end

    # Filter by active status
    if params[:status].present?
      @products = params[:status] == 'active' ? @products.active : @products.inactive
    end

    @categories     = ProductCategory.active.ordered
    @active_count   = Product.active.count
    @inactive_count = Product.inactive.count
  end

  def show; end

  def export
    @products = Product.includes(:product_category, :base_uom).ordered

    package = Axlsx::Package.new
    wb      = package.workbook
    styles  = wb.styles

    hdr  = styles.add_style(bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
             alignment: { horizontal: :center, vertical: :center })
    even = styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd  = styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num  = styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
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
          p.brand,
          p.pack_code,
          p.description,
          p.material_code,
          p.product_code,
          p.hsn_code,
          p.gst_rate,
          p.mrp,
          p.active
        ], style: [row_style, row_style, row_style, row_style, row_style,
                   row_style, row_style, row_style, num, num, row_style],
           height: 18)
      end

      sheet.column_widths 22, 10, 18, 12, 34, 18, 18, 12, 10, 12, 8
    end

    filename = "products_export_#{Date.today.strftime('%Y%m%d')}.xlsx"
    send_data package.to_stream.read,
      filename:    filename,
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  def new
    @product    = Product.new(active: true, gst_rate: 18.0)
    @categories = ProductCategory.active.ordered
    @uoms       = Uom.active.ordered
  end

  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to setup_product_path(@product), notice: 'Product created successfully.'
    else
      @categories = ProductCategory.active.ordered
      @uoms       = Uom.active.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = ProductCategory.active.ordered
    @uoms       = Uom.active.ordered
  end

  def update
    if @product.update(product_params)
      redirect_to setup_product_path(@product), notice: 'Product updated successfully.'
    else
      @categories = ProductCategory.active.ordered
      @uoms       = Uom.active.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.destroy
    redirect_to setup_products_path, notice: 'Product deleted.'
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(
      :product_category_id, :base_uom_id,
      :brand, :material_code, :product_code, :pack_code,
      :description, :hsn_code, :gst_rate, :active,
      :mrp, :metadata
    )
  end
end