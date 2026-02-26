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
      :description, :hsn_code, :gst_rate, :active
    )
  end
end
