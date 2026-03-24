# app/controllers/inventory/tinting_machine_controller.rb
class Inventory::TintingMachineController < Inventory::BaseController

  DISPENSE_STEP_ML = 50

  before_action :set_brand,    only: [:show, :load_canister, :adjust, :remove_canister]
  before_action :set_canister, only: [:adjust, :remove_canister]

  # GET /inventory/tinting_machine
  def index
    @brands          = Brand.active.ordered
    @brand_summaries = @brands.index_with { |b| canisters_for(b.id) }
  end

  # GET /inventory/tinting_machine/:brand_id
  def show
    @canisters         = canisters_for(@brand.id)
    @slot_count        = slot_count_for(@brand)
    @tintable_products = tintable_products_in_stock
  end

  # POST /inventory/tinting_machine/:brand_id/load
  # Loads a tintable product into a canister slot — deducts 1 unit from stock
  def load_canister
    product = Product.find_by(id: params[:product_id])
    return render json: { success: false, error: 'Product not found' } unless product
    return render json: { success: false, error: 'Not a tintable product' } unless tintable?(product)

    stock = StockLevel.for_org(@organisation.id).find_by(product_id: product.id)
    if stock.nil? || stock.quantity < 1
      return render json: { success: false, error: "No stock available for #{product.description}" }
    end

    slot_num = params[:slot_number].to_i
    vol_ml   = params[:volume_ml].to_i
    vol_ml   = TintingMachineCanister.volume_from_pack_code(product.pack_code) if vol_ml <= 0

    ActiveRecord::Base.transaction do
      canister = TintingMachineCanister.find_or_initialize_by(
        organisation_id: @organisation.id,
        brand_id:        @brand.id,
        slot_number:     slot_num
      )
      canister.update!(
        product:             product,
        loaded_by:           current_user,
        loaded_at:           Time.current,
        initial_volume_ml:   vol_ml,
        dispensed_volume_ml: 0,
        status:              'active'
      )

      # Deduct 1 unit from stock
      StockLedger.create!(
        organisation:   @organisation,
        product:        product,
        user:           current_user,
        entry_type:     'adjustment',
        quantity:       -1,
        unit_cost:      stock.avg_cost || 0,
        notes:          "Loaded into tinting machine — #{@brand.name} Slot #{slot_num}",
        reference_type: 'TintingMachineCanister',
        reference_id:   canister.id
      )
    end

    render json: { success: true, message: "#{product.description} loaded into Slot #{slot_num}" }
  rescue => e
    render json: { success: false, error: e.message }
  end

  # PATCH /inventory/tinting_machine/:brand_id/adjust/:id
  # ± DISPENSE_STEP_ML adjustment — no logging
  def adjust
    step = DISPENSE_STEP_ML

    if params[:direction] == 'subtract'
      new_d = [@canister.dispensed_volume_ml + step, @canister.initial_volume_ml].min
    else
      new_d = [@canister.dispensed_volume_ml - step, 0].max
    end

    @canister.update!(dispensed_volume_ml: new_d)
    @canister.refresh_status!

    render json: {
      success:       true,
      remaining_ml:  @canister.remaining_ml,
      level_percent: @canister.level_percent,
      level_status:  @canister.level_status.to_s,
      level_color:   @canister.level_color
    }
  rescue => e
    render json: { success: false, error: e.message }
  end

  # DELETE /inventory/tinting_machine/:brand_id/remove/:id
  # Clears a canister slot — no stock adjustment on removal
  def remove_canister
    name = @canister.product&.description || "Slot #{@canister.slot_number}"
    slot = @canister.slot_number
    @canister.update!(
      product_id:          nil,
      status:              'empty',
      loaded_at:           nil,
      loaded_by_id:        nil,
      dispensed_volume_ml: 0,
      initial_volume_ml:   0
    )
    render json: { success: true, message: "#{name} removed from Slot #{slot}" }
  rescue => e
    render json: { success: false, error: e.message }
  end

  private

  def set_brand
    @brand = Brand.find(params[:brand_id])
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Brand not found' }, status: :not_found
  end

  def set_canister
    @canister = TintingMachineCanister.for_org(@organisation.id).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Canister not found' }, status: :not_found
  end

  def canisters_for(brand_id)
    TintingMachineCanister
      .for_org(@organisation.id)
      .for_brand(brand_id)
      .includes(:product, :loaded_by)
      .ordered
  end

  def slot_count_for(brand)
    brand.name.downcase.include?('salimar') ? 12 : 16
  end

  def tintable_products_in_stock
    Product
      .for_org(@organisation)
      .joins("INNER JOIN stock_levels ON stock_levels.product_id = products.id
              AND stock_levels.organisation_id = #{@organisation.id.to_i}")
      .where("products.metadata->>'tint' = 'true'")
      .where("products.metadata->>'family_colour' IS NOT NULL
              AND products.metadata->>'family_colour' != ''")
      .where('stock_levels.quantity >= 1')
      .includes(:brand, :product_category)
      .order('products.description ASC')
  end

  def tintable?(product)
    product.metadata&.dig('tint').to_s == 'true' &&
      product.metadata&.dig('family_colour').present?
  end
end