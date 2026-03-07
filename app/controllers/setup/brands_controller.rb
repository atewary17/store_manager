# app/controllers/setup/brands_controller.rb
class Setup::BrandsController < Setup::BaseController

  before_action :set_brand, only: [:show, :edit, :update, :destroy]

  def index
    @brands = Brand.ordered.limit(20)
    @brands = @brands.where(active: params[:status] != 'inactive')
    @total_count    = Brand.count
    @active_count   = Brand.where(active: true).count
    @inactive_count = Brand.where(active: false).count
  end

  def new
    @brand = Brand.new
  end

  def show
  end

  def edit
  end

  def create
    @brand = Brand.new(brand_params)
    if @brand.save
      redirect_to setup_brands_path, notice: 'Brand created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @brand.update(brand_params)
      redirect_to setup_brands_path, notice: 'Brand updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @brand.can_delete?
      @brand.destroy
      redirect_to setup_brands_path, notice: 'Brand deleted.'
    else
      redirect_to setup_brands_path,
        alert: 'Cannot delete — brand is used by products or shades.'
    end
  end

  private

  def set_brand
    @brand = Brand.find(params[:id])
  end

  def brand_params
    params.require(:brand).permit(:name, :short_name, :description, :active)
  end

end
