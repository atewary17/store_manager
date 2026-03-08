# app/controllers/inventory/opening_stocks_controller.rb
class Inventory::OpeningStocksController < Inventory::BaseController

  # GET /inventory/opening_stock
  def new
    # Products that don't have an opening stock entry yet for this org
    entered_product_ids = StockLedger
      .for_org(@organisation.id)
      .of_type('opening')
      .pluck(:product_id)

    @products = Product
      .includes(:brand, :product_category, :base_uom)
      .active
      .where.not(id: entered_product_ids)
      .joins(:brand)
      .order('brands.name, products.description')

    @categories = ProductCategory.active.ordered
    @brands     = Brand.active.ordered
  end

  # POST /inventory/opening_stock
  def create
    entries = params[:entries] || {}
    entered = 0
    errors  = []

    ActiveRecord::Base.transaction do
      entries.each do |product_id, attrs|
        qty  = attrs[:quantity].to_s.strip
        cost = attrs[:unit_cost].to_s.strip

        next if qty.blank? || qty.to_f == 0

        product = Product.find_by(id: product_id)
        unless product
          errors << "Product ##{product_id} not found"
          next
        end

        # Guard: don't allow duplicate opening stock
        if StockLedger.for_org(@organisation.id)
                      .of_type('opening')
                      .exists?(product_id: product_id)
          errors << "#{product.display_name} already has an opening stock entry"
          next
        end

        StockLedger.create!(
          organisation: @organisation,
          product:      product,
          user:         current_user,
          entry_type:   'opening',
          quantity:     qty.to_f,
          unit_cost:    cost.present? ? cost.to_f : nil,
          notes:        attrs[:notes].to_s.strip.presence
        )
        entered += 1
      end
    end

    if errors.any?
      flash[:alert] = "#{errors.count} error(s): #{errors.first(3).join('; ')}"
    end

    if entered > 0
      redirect_to inventory_stock_levels_path,
        notice: "Opening stock saved for #{entered} product(s)."
    else
      redirect_to new_inventory_opening_stock_path,
        alert: flash[:alert] || "No quantities were entered."
    end
  end

  # GET /inventory/opening_stock/:product_id/ledger
  def ledger
    @product = Product.find(params[:product_id])
    @entries = StockLedger
      .for_org(@organisation.id)
      .for_product(@product.id)
      .includes(:user)
      .recent
  end

end
