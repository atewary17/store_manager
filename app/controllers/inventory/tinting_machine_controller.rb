# app/controllers/inventory/tinting_machine_controller.rb
class Inventory::TintingMachineController < Inventory::BaseController

  DISPENSE_STEP_PCT = 25  # each ± tap moves 25% of initial volume

  SUPPORTED_TINTING_BRANDS = [
    'Asian Paints', 'Salimar Paints', 'Berger Paints', 'Nerolac Paints', 'Birla Opus'
  ].freeze

  before_action :set_brand,    only: [:show, :load_canister, :adjust, :reload_last]
  before_action :set_canister, only: [:adjust]

  def index
    @brands          = Brand.active.ordered
                            .where(name: SUPPORTED_TINTING_BRANDS)
    @brand_summaries = @brands.index_with { |b| canisters_for(b.id) }
  end

  def show
    @canisters         = canisters_for(@brand.id)
    @slot_count        = slot_count_for(@brand)
    # Fix #5: only show tintable products for THIS brand
    @tintable_products = tintable_products_in_stock(@brand)
  end

  # POST /inventory/tinting_machine/:brand_id/load
  def load_canister
    product = Product.find_by(id: params[:product_id])
    return render json: { success: false, error: 'Product not found' } unless product
    return render json: { success: false, error: 'Not a tintable colourant — only pigment/colorant products can be loaded into the tinting machine' } unless tintable?(product)

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
        status:              'active',
        # Store last colour in metadata when loading — also clears previous last
        metadata:            (canister.metadata || {}).merge(
          'last_family_colour' => product.metadata['family_colour'].presence,
          'last_product_name'  => product.description
        ).compact
      )

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

    ActivityLogger.log(
      organisation:     @organisation,
      user:             current_user,
      activity_type:    'tinting_update',
      activity_subtype: 'updated',
      description:      "Tinting machine loaded — #{@brand.name} Slot #{slot_num}: #{product.description}",
      quantity_litres:  0,
      reference:        TintingMachineCanister.find_by(organisation_id: @organisation.id,
                                                       brand_id: @brand.id, slot_number: slot_num),
      metadata:         { brand: @brand.name, slot: slot_num, product: product.description }
    )

    render json: { success: true, message: "#{product.description} loaded into Slot #{slot_num}" }
  rescue => e
    render json: { success: false, error: e.message }
  end

  # PATCH /inventory/tinting_machine/:brand_id/adjust/:id
  # Each tap subtracts/adds 25% of the canister's initial volume.
  # Warns before the last step that will empty the canister.
  def adjust
    step = (@canister.initial_volume_ml * DISPENSE_STEP_PCT / 100.0).round

    if params[:direction] == 'subtract'
      new_d = [@canister.dispensed_volume_ml + step, @canister.initial_volume_ml].min
    else
      new_d = [@canister.dispensed_volume_ml - step, 0].max
    end

    will_be_empty = new_d >= @canister.initial_volume_ml

    # Save last colour to metadata BEFORE clearing, so history is kept
    meta_update = @canister.metadata || {}
    if will_be_empty && @canister.product_id.present?
      fc   = @canister.product.metadata['family_colour'].presence
      meta_update = meta_update.merge(
        'last_family_colour' => fc,
        'last_product_name'  => @canister.product.description
      ).compact
    end

    @canister.update!(dispensed_volume_ml: new_d, metadata: meta_update)

    # If empty — clear the product from the slot (keep metadata for history)
    if will_be_empty
      @canister.update!(
        product_id:   nil,
        loaded_at:    nil,
        loaded_by_id: nil,
        status:       'empty'
      )
    else
      @canister.refresh_status!
    end

    ActivityLogger.log(
      organisation:     @organisation,
      user:             current_user,
      activity_type:    'tinting_update',
      activity_subtype: will_be_empty ? 'updated' : 'updated',
      description:      "Canister #{params[:direction] == 'subtract' ? 'dispensed' : 'restored'} — " \
                        "#{@brand.name} Slot #{@canister.slot_number}" \
                        "#{will_be_empty ? ' (now empty)' : ''}",
      quantity_litres:  0,
      reference:        @canister,
      metadata: {
        brand:        @brand.name,
        slot:         @canister.slot_number,
        direction:    params[:direction],
        remaining_ml: @canister.remaining_ml,
        now_empty:    will_be_empty,
        product:      meta_update['last_product_name']
      }.compact
    ) rescue nil

    render json: {
      success:        true,
      remaining_ml:   @canister.remaining_ml,
      level_percent:  @canister.level_percent,
      level_status:   @canister.level_status.to_s,
      level_color:    @canister.level_color,
      now_empty:      will_be_empty,
      last_colour:    meta_update['last_family_colour']
    }
  rescue => e
    render json: { success: false, error: e.message }
  end

  # POST /inventory/tinting_machine/:brand_id/reload_last/:slot_number
  # Reloads the last colourant that was in this slot, if stock exists.
  def reload_last
    slot_num  = params[:slot_number].to_i
    canister  = TintingMachineCanister.for_org(@organisation.id)
                                      .find_by(brand_id: @brand.id, slot_number: slot_num)

    unless canister
      return render json: { success: false, error: "Slot #{slot_num} not found" }
    end

    last_name = canister.metadata&.dig('last_product_name').presence
    unless last_name
      return render json: { success: false, error: 'No previous colourant recorded for this slot' }
    end

    # Find the product by description match within this brand
    product = Product
                .for_org(@organisation)
                .where(brand_id: @brand.id)
                .where("products.metadata->>'tint' = 'true'")
                .find_by(description: last_name)

    unless product
      return render json: {
        success: false,
        error:   ""#{last_name}" is no longer in the product catalogue"
      }
    end

    stock = StockLevel.for_org(@organisation.id).find_by(product_id: product.id)
    if stock.nil? || stock.quantity < 1
      return render json: {
        success:    false,
        no_stock:   true,
        error:      "No stock available for #{product.description}. Please purchase more stock first."
      }
    end

    vol_ml = TintingMachineCanister.volume_from_pack_code(product.pack_code)

    ActiveRecord::Base.transaction do
      canister.update!(
        product:             product,
        loaded_by:           current_user,
        loaded_at:           Time.current,
        initial_volume_ml:   vol_ml,
        dispensed_volume_ml: 0,
        status:              'active',
        metadata:            (canister.metadata || {}).merge(
          'last_family_colour' => product.metadata['family_colour'].presence,
          'last_product_name'  => product.description
        ).compact
      )

      StockLedger.create!(
        organisation:   @organisation,
        product:        product,
        user:           current_user,
        entry_type:     'adjustment',
        quantity:       -1,
        unit_cost:      stock.avg_cost || 0,
        notes:          "Reloaded into tinting machine — #{@brand.name} Slot #{slot_num}",
        reference_type: 'TintingMachineCanister',
        reference_id:   canister.id
      )
    end

    ActivityLogger.log(
      organisation:     @organisation,
      user:             current_user,
      activity_type:    'tinting_update',
      activity_subtype: 'updated',
      description:      "Tinting machine reloaded — #{@brand.name} Slot #{slot_num}: #{product.description}",
      quantity_litres:  0,
      reference:        canister,
      metadata:         { brand: @brand.name, slot: slot_num, product: product.description }
    )

    render json: {
      success: true,
      message: "#{product.description} reloaded into Slot #{slot_num}"
    }
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
    @canister = TintingMachineCanister
                  .for_org(@organisation.id)
                  .includes(:product)
                  .find(params[:id])
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

  # Fix #5: scope tintable products to this brand only
  def tintable_products_in_stock(brand)
    Product
      .for_org(@organisation)
      .joins("INNER JOIN stock_levels ON stock_levels.product_id = products.id
              AND stock_levels.organisation_id = #{@organisation.id.to_i}")
      .where("products.metadata->>'tint' = 'true'")
      .where("products.metadata->>'family_colour' IS NOT NULL
              AND products.metadata->>'family_colour' != ''")
      .where("products.metadata->>'is_tinting_base' IS DISTINCT FROM 'true'")
      .where('stock_levels.quantity >= 1')
      .where(brand_id: brand.id)
      .includes(:brand, :product_category)
      .order('products.description ASC')
  end

  def tintable?(product)
    product.metadata&.dig('tint').to_s == 'true' &&
      product.metadata&.dig('family_colour').present? &&
      product.metadata&.dig('is_tinting_base') != true
  end
end