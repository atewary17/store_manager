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
      # LEFT JOIN brand — preserves pending products that may have no brand
      filtered = filtered
        .joins('INNER JOIN products ON products.id = stock_levels.product_id')
        .joins('LEFT OUTER JOIN brands ON brands.id = products.brand_id')
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
               when 'qty_asc'      then 'stock_levels.quantity ASC'
               when 'qty_desc'     then 'stock_levels.quantity DESC'
               when 'entry_latest' then 'le.last_entry_at DESC NULLS LAST'
               when 'entry_oldest' then 'le.last_entry_at ASC NULLS LAST'
               else                     Arel.sql("COALESCE(brands.name, 'zzz') ASC, products.description ASC")
               end

    # PostgreSQL requires ORDER BY columns to appear in SELECT when using DISTINCT.
    sort_select = case params[:sort]
                  when 'qty_asc', 'qty_desc'
                    'stock_levels.id, stock_levels.quantity'
                  when 'entry_latest', 'entry_oldest'
                    'stock_levels.id, le.last_entry_at'
                  else
                    "stock_levels.id, COALESCE(brands.name, 'zzz') as brand_sort, products.description"
                  end

    org_id = @organisation.id.to_i
    ledger_join = %w[entry_latest entry_oldest].include?(params[:sort]) ?
      "LEFT JOIN (SELECT product_id, MAX(created_at) AS last_entry_at FROM stock_ledgers WHERE organisation_id = #{org_id} GROUP BY product_id) le ON le.product_id = products.id" :
      nil

    # Use LEFT JOIN for brand — AI-enriched pending products may have no brand
    # INNER JOIN would silently exclude them from the stock dashboard
    sorted_ids = filtered
      .joins('INNER JOIN products ON products.id = stock_levels.product_id')
      .joins('LEFT OUTER JOIN brands ON brands.id = products.brand_id')
      .then { |s| ledger_join ? s.joins(ledger_join) : s }
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

    @categories   = ProductCategory.active.ordered
    @brands       = Brand.active.ordered
    @stock_locked = @organisation.stock_updates_locked?

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
                                     locals:  { levels: @levels, last_entry: @last_entry,
                                                stock_locked: @stock_locked },
                                     formats: [:html])
        list_html = render_to_string(partial: 'inventory/stock_levels/list_rows',
                                     locals:  { levels: @levels, last_entry: @last_entry,
                                                stock_locked: @stock_locked },
                                     formats: [:html])
        render json: { html: card_html, list_html: list_html, has_more: @has_more, page: @page }
      end
    end
  end

  # GET /inventory/stock_levels/export
  # Exports all in-stock items (qty > 0) for current org as Excel.
  # Fields: Product, Brand, Category, Material Code, Quantity, UOM, Stock Value
  def export
    require 'axlsx'

    # In-stock only — qty > 0, with all needed associations
    levels = StockLevel
      .for_org(@organisation.id)
      .in_stock
      .joins('INNER JOIN products ON products.id = stock_levels.product_id')
      .joins('LEFT OUTER JOIN brands ON brands.id = products.brand_id')
      .joins('LEFT OUTER JOIN product_categories ON product_categories.id = products.product_category_id')
      .joins('LEFT OUTER JOIN uoms ON uoms.id = products.base_uom_id')
      .includes(product: [:brand, :product_category, :base_uom])
      .order(Arel.sql("COALESCE(brands.name, 'zzz') ASC, products.description ASC"))

    package = Axlsx::Package.new
    wb      = package.workbook

    hdr  = wb.styles.add_style(
      bg_color: '1F3864', fg_color: 'FFFFFF', b: true, sz: 11,
      alignment: { horizontal: :center, vertical: :center }
    )
    even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10)
    odd  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10)
    num  = wb.styles.add_style(
      bg_color: 'FFFFFF', fg_color: '404040', sz: 10,
      alignment: { horizontal: :right }
    )
    num_even = wb.styles.add_style(
      bg_color: 'F7F9FC', fg_color: '404040', sz: 10,
      alignment: { horizontal: :right }
    )
    txt  = wb.styles.add_style(bg_color: 'FFFFFF', fg_color: '404040', sz: 10, format_code: '@')
    txt_even = wb.styles.add_style(bg_color: 'F7F9FC', fg_color: '404040', sz: 10, format_code: '@')

    wb.add_worksheet(name: 'Stock') do |sheet|
      sheet.add_row(
        ['Product', 'Brand', 'Category', 'Material Code',
         'Quantity', 'UOM', 'Avg Cost (₹)', 'Stock Value (₹)'],
        style: hdr, height: 24
      )

      levels.each_with_index do |sl, i|
        p          = sl.product
        row_style  = i.even? ? even : odd
        n_style    = i.even? ? num_even : num
        code_style = i.even? ? txt_even : txt
        qty        = sl.quantity.to_f.round(3)
        avg_cost   = sl.avg_cost.to_f.round(2)
        value      = (qty * avg_cost).round(2)

        sheet.add_row([
          p.description,
          p.brand&.name,
          p.product_category&.name,
          p.material_code.to_s,
          qty,
          p.base_uom&.short_name,
          avg_cost,
          value
        ], style: [row_style, row_style, row_style, code_style,
                   n_style, row_style, n_style, n_style],
           height: 18)
      end

      # Summary row at the bottom
      total_value = levels.sum('stock_levels.quantity * COALESCE(stock_levels.avg_cost, 0)').round(2)
      total_qty   = levels.sum(:quantity).round(3)
      summary_style = wb.styles.add_style(
        bg_color: 'E8F0FE', fg_color: '1F3864', b: true, sz: 10,
        alignment: { horizontal: :right }
      )
      summary_label = wb.styles.add_style(
        bg_color: 'E8F0FE', fg_color: '1F3864', b: true, sz: 10
      )
      sheet.add_row(
        ["#{levels.count} products", '', '', 'TOTAL',
         total_qty, '', '', total_value],
        style: [summary_label, summary_label, summary_label, summary_label,
                summary_style, summary_style, summary_style, summary_style],
        height: 20
      )

      sheet.column_widths 36, 18, 20, 20, 12, 8, 14, 16
    end

    send_data package.to_stream.read,
      filename:    "stock_#{@organisation.name.parameterize}_#{Date.today.strftime('%Y%m%d')}.xlsx",
      type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      disposition: 'attachment'
  end

  # POST /inventory/stock_levels/:id/quick_adjust
  def quick_adjust
    if @organisation.stock_updates_locked?
      render json: { error: 'Stock updates are locked by your administrator.' },
             status: :forbidden
      return
    end

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

    begin
      ActivityLogger.log(
        organisation:     @organisation,
        user:             current_user,
        activity_type:    'stock_adjustment',
        activity_subtype: 'manual',
        description:      "Quick stock adjust #{delta > 0 ? '+1' : '-1'} — #{@level.product.description}",
        reference:        @level.product,
        metadata:         { product_id: @level.product_id, delta: delta, new_qty: @level.quantity.to_f }
      )
    rescue => e
      Rails.logger.warn("[ActivityLog] stock_adjustment #{@level.id}: #{e.message}")
    end

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