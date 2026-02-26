# app/controllers/setup/uoms_controller.rb
class Setup::UomsController < Setup::BaseController
  before_action :set_uom, only: [:show, :edit, :update, :destroy]

  def index
    @uoms = Uom.ordered
    @active_count   = @uoms.count(&:active?)
    @inactive_count = @uoms.count { |u| !u.active? }
  end

  def show; end

  def new
    @uom = Uom.new
  end

  def create
    @uom = Uom.new(uom_params)
    if @uom.save
      redirect_to setup_uom_path(@uom), notice: 'Unit of measure created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @uom.update(uom_params)
      redirect_to setup_uom_path(@uom), notice: 'Unit of measure updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @uom.can_delete?
      @uom.destroy
      redirect_to setup_uoms_path, notice: 'Unit of measure deleted.'
    else
      redirect_to setup_uom_path(@uom),
        alert: "Cannot delete — #{@uom.products.count} product(s) use this UOM."
    end
  end

  private

  def set_uom
    @uom = Uom.find(params[:id])
  end

  def uom_params
    params.require(:uom).permit(:name, :short_name, :active)
  end
end
