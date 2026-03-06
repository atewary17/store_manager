# app/controllers/setup/product_categories_controller.rb
class Setup::ProductCategoriesController < Setup::BaseController
  before_action :set_category, only: [:show, :edit, :update, :destroy]

  def index
    @categories     = ProductCategory.includes(:products).ordered.limit(20)
    @total_count    = ProductCategory.count
    @active_count   = ProductCategory.where(active: true).count
    @inactive_count = ProductCategory.where(active: false).count
  end

  def show
    @products = @category.products.includes(:base_uom).ordered
  end

  def new
    @category = ProductCategory.new
  end

  def create
    @category = ProductCategory.new(category_params)
    if @category.save
      redirect_to setup_product_category_path(@category),
        notice: 'Product category created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @category.update(category_params)
      redirect_to setup_product_category_path(@category),
        notice: 'Product category updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.can_delete?
      @category.destroy
      redirect_to setup_product_categories_path, notice: 'Category deleted.'
    else
      redirect_to setup_product_category_path(@category),
        alert: "Cannot delete — #{@category.products.count} product(s) belong to this category."
    end
  end

  private

  def set_category
    @category = ProductCategory.find(params[:id])
  end

  def category_params
    allowed = %i[name description active is_paint_type]
    allowed << :import_key       if ProductCategory.column_names.include?('import_key')
    allowed << :import_key_label if ProductCategory.column_names.include?('import_key_label')
    params.require(:product_category).permit(*allowed)
  end
end