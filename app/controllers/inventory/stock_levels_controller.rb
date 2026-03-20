# app/controllers/inventory/stock_levels_controller.rb
class Inventory::StockLevelsController < Inventory::BaseController
  include ActionView::Helpers::NumberHelper

  CARDS_PER_PAGE = 50

  # GET /inventory/stock_levels
  def index
    # Use a clean base scope (no joins/includes) for accurate aggregate counts.
    # Joins are added separately only for filtering and ordering.
    base_scope = StockLevel.for_org(@organisation.id)

    # ── Build filter scope (with joins only when needed) ──
    filtered = base_scope

    if params[:category_id].present? || params[:brand_id].present? || params[:q].present?
      filtered = filtered.joins(product: [:brand])
    end

    filtered = filtered.where(products: { product_category_id: params[:category_id] }) if params[:category_id].present?
    filtered = filtered.where(products: { brand_id: params[:brand_id] })               if params[:brand_id].present?

    if params[:q].present?
      term     = "%#{params[:q].downcase}%"
      filtered = filtered.where(
        'LOWER(products.description) LIKE :q OR LOWER(products.material_code) LIKE :q
         OR LOWER(products.pack_code) LIKE :q OR LOWER(brands.name) LIKE :q', q: term
      )
    end

    case params[:stock_status]
    when 'in_stock'     then filtered = filtered.in_stock
    when 'out_of_stock' then filtered = filtered.out_of_stock
    when 'low_stock'    then filtered = filtered.where('stock_levels.quantity > 0 AND stock_levels.quantity <= 5')
    end

    # ── Stats — use plain unscoped counts directly on the org's stock_levels ──
    # filtered may have joins that cause duplicate rows; for stats we always
    # go back to the clean base_scope and apply only stock_status filtering.
    stats_scope = base_scope
    case params[:stock_status]
    when 'in_stock'     then stats_scope = stats_scope.in_stock
    when 'out_of_stock' then stats_scope = stats_scope.out_of_stock
    when 'low_stock'    then stats_scope = stats_scope.where('stock_levels.quantity > 0 AND stock_levels.quantity <= 5')
    end

    # If category/brand/search filters are active, restrict stats to matching product_ids
    if params[:category_id].present? || params[:brand_id].present? || params[:q].present?
      matching_product_ids = filtered.joins(:product).pluck('stock_levels.product_id').uniq
      stats_scope = stats_scope.where(product_id: matching_product_ids)
    end

    @total_products     = stats_scope.count
    @in_stock_count     = stats_scope.in_stock.count
    @out_of_stock_count = stats_scope.out_of_stock.count
    @total_value        = stats_scope.sum('quantity * COALESCE(avg_cost, 0)').round(0)
    @total_units        = stats_scope.in_stock.sum(:quantity).round(0)

    # ── Sort ──
    sort_sql = case params[:sort]
               when 'qty_asc'  then 'stock_levels.quantity ASC'
               when 'qty_desc' then 'stock_levels.quantity DESC'
               else                 'brands.name ASC, products.description ASC'
               end

    # PostgreSQL requires ORDER BY columns to appear in SELECT when using DISTINCT.
    # Solution: select the sort columns alongside the id, then extract just the ids.
    sort_select = case params[:sort]
                  when 'qty_asc', 'qty_desc'
                    'stock_levels.id, stock_levels.quantity'
                  else
                    'stock_levels.id, brands.name, products.description'
                  end

    sorted_ids = filtered
      .joins(product: :brand)
      .select(sort_select)
      .order(Arel.sql(sort_sql))
      .map(&:id)
      .uniq

    # ── Pagination ──
    @page        = [params[:page].to_i, 1].max
    @total_pages = [(@total_products.to_f / CARDS_PER_PAGE).ceil, 1].max
    page_ids     = sorted_ids.slice((@page - 1) * CARDS_PER_PAGE, CARDS_PER_PAGE) || []
    @has_more    = @page < @total_pages

    # Load only the paginated records with includes for rendering
    id_order     = page_ids.each_with_index.map { |id, i| "WHEN #{id} THEN #{i}" }.join(' ')
    @levels      = StockLevel
      .where(id: page_ids)
      .includes(product: [:brand, :product_category, :base_uom])
      .order(page_ids.any? ? Arel.sql("CASE stock_levels.id #{id_order} END") : 'stock_levels.id')

    @categories = ProductCategory.active.ordered
    @brands     = Brand.active.ordered

    # Last ledger entry date per product (for display on cards)
    pids = @levels.map(&:product_id)
    @last_entry = pids.any? ? StockLedger.for_org(@organisation.id)
                                          .where(product_id: pids)
                                          .group(:product_id)
                                          .maximum(:created_at) : {}

    respond_to do |format|
      format.html
      format.json do
        card_html = render_to_string(partial: 'inventory/stock_levels/cards',
                                     locals:  { levels: @levels, last_entry: @last_entry },
                                     formats: [:html])
        list_html = render_to_string(partial: 'inventory/stock_levels/list_rows',
                                     locals:  { levels: @levels, last_entry: @last_entry },
                                     formats: [:html])
        render json: { html: card_html, list_html: list_html, has_more: @has_more, page: @page }
      end
    end
  end

  # POST /inventory/stock_levels/:id/quick_adjust
  def quick_adjust
    @level  = StockLevel.for_org(@organisation.id).find(params[:id])
    delta   = params[:delta].to_f

    unless [-1.0, 1.0].include?(delta)
      render json: { error: 'Invalid delta — must be +1 or -1' }, status: :unprocessable_entity
      return
    end

    if delta < 0 && @level.quantity + delta < 0
      render json: { error: 'Stock cannot go below zero', qty: @level.quantity.to_f },
             status: :unprocessable_entity
      return
    end

    StockLedger.create!(
      organisation: @organisation,
      product:      @level.product,
      user:         current_user,
      entry_type:   'adjustment',
      quantity:     delta,
      notes:        "Quick adjust #{delta > 0 ? '+1' : '-1'} via stock dashboard"
    )

    @level.reload

    render json: {
      qty:      @level.quantity.to_f,
      qty_fmt:  number_with_precision(@level.quantity, precision: 3, strip_insignificant_zeros: true),
      in_stock: @level.in_stock?,
      value:    number_with_delimiter(@level.stock_value.round(0))
    }

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

end