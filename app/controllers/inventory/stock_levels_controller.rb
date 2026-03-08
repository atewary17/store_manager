# app/controllers/inventory/stock_levels_controller.rb
class Inventory::StockLevelsController < Inventory::BaseController

  # GET /inventory/stock_levels
  def index
    @levels = StockLevel
      .for_org(@organisation.id)
      .includes(product: [:brand, :product_category, :base_uom])
      .ordered

    # Filters
    if params[:category_id].present?
      @levels = @levels.where(products: { product_category_id: params[:category_id] })
    end

    if params[:brand_id].present?
      @levels = @levels.where(products: { brand_id: params[:brand_id] })
    end

    case params[:stock_status]
    when 'in_stock'     then @levels = @levels.in_stock
    when 'out_of_stock' then @levels = @levels.out_of_stock
    end

    @total_products   = @levels.count
    @in_stock_count   = @levels.in_stock.count
    @out_of_stock_count = @levels.out_of_stock.count
    @total_value      = @levels.sum(&:stock_value)

    @categories = ProductCategory.active.ordered
    @brands     = Brand.active.ordered
  end

end
