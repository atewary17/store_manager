# app/controllers/reports/stock_reports_controller.rb
class Reports::StockReportsController < Reports::BaseController

  before_action :set_active_tab

  # GET /reports/stock_reports
  def index
    case @tab
    when 'movement'  then load_movement
    when 'velocity'  then load_velocity
    when 'low_stock' then load_low_stock
    else                  load_register
    end
  end

  private

  def set_active_tab
    @tab = params[:tab].presence || 'register'
  end

  # ── Tab 1: Stock Register (Current) ──────────────────────────────────────
  def load_register
    levels = StockLevel
               .for_org(@organisation.id)
               .joins(product: [:brand, :product_category])
               .includes(product: [:brand, :product_category, :base_uom])
               .order('brands.name, products.description')

    @total_products     = levels.count
    @in_stock_count     = levels.count { |l| l.quantity > 0 }
    @out_of_stock_count = levels.count { |l| l.quantity <= 0 }
    @total_stock_value  = levels.sum(&:stock_value).round(2)

    # Value by category for donut chart
    by_cat = levels.group_by { |l| l.product.product_category.name }
    @chart_labels = by_cat.keys
    @chart_data   = by_cat.values.map { |ls| ls.sum(&:stock_value).round(2) }

    @rows = levels.map do |l|
      {
        brand:    l.product.brand&.name || '—',
        category: l.product.product_category&.name || '—',
        product:  l.product.description,
        code:     l.product.full_code,
        quantity: l.quantity.to_f,
        uom:      l.product.base_uom&.short_name || '—',
        avg_cost: l.avg_cost.to_f,
        value:    l.stock_value
      }
    end
  end

  # ── Tab 2: Stock Movement ─────────────────────────────────────────────────
  def load_movement
    @product_id = params[:product_id].presence

    entries = StockLedger
                .for_org(@organisation.id)
                .where(created_at: @date_from.beginning_of_day..@date_to.end_of_day)
                .includes(product: :brand)
                .order(created_at: :desc)

    entries = entries.for_product(@product_id) if @product_id.present?

    # Materialise once
    all = entries.to_a

    @txn_count = all.count
    @total_in  = all.select(&:in?).sum { |e| e.quantity.to_f }.round(2)
    @total_out = all.select(&:out?).sum { |e| e.quantity.to_f.abs }.round(2)

    # Products available for filter dropdown
    @products_for_select = StockLevel
                             .for_org(@organisation.id)
                             .joins(product: :brand)
                             .includes(product: :brand)
                             .order('brands.name, products.description')
                             .map { |l| [l.product.display_name, l.product_id] }

    # Daily net movement for chart
    daily = all.group_by { |e| e.created_at.to_date }
               .transform_values { |es| es.sum { |e| e.quantity.to_f }.round(2) }
               .sort.to_h
    @chart_labels = daily.keys.map { |d| d.strftime('%d %b') }
    @chart_data   = daily.values

    @rows = all.map do |e|
      {
        date:      e.created_at,
        product:   e.product.display_name,
        type:      e.entry_type,
        quantity:  e.quantity.to_f,
        unit_cost: e.unit_cost&.to_f,
        notes:     e.notes
      }
    end
  end

  # ── Tab 3: Fast / Slow Moving ─────────────────────────────────────────────
  def load_velocity
    @days = params[:days].presence&.to_i || 30
    since = @days.days.ago.to_date

    items = SalesInvoiceItem
              .joins(:sales_invoice)
              .where(
                sales_invoices: {
                  organisation_id: @organisation.id,
                  status:          'confirmed',
                  invoice_date:    since..Date.today
                }
              )
              .where(line_type: 'product')
              .joins(product: :brand)
              .group('products.id, products.description, brands.name')
              .select(
                'products.id,
                 products.description AS product_desc,
                 brands.name          AS brand_name,
                 SUM(sales_invoice_items.quantity)    AS total_qty,
                 SUM(sales_invoice_items.total_amount) AS total_revenue,
                 COUNT(DISTINCT sales_invoice_items.sales_invoice_id) AS invoice_count'
              )
              .order('total_qty DESC')
              .to_a

    @total_products_sold = items.length
    top10  = items.first(10)
    slow10 = items.last(10).reverse

    @fast_labels = top10.map  { |r| truncate_label("#{r.brand_name} #{r.product_desc}") }
    @fast_data   = top10.map  { |r| r.total_qty.to_f.round(3) }
    @slow_labels = slow10.map { |r| truncate_label("#{r.brand_name} #{r.product_desc}") }
    @slow_data   = slow10.map { |r| r.total_qty.to_f.round(3) }

    @rows = items.map do |r|
      {
        brand:    r.brand_name,
        product:  r.product_desc,
        qty:      r.total_qty.to_f.round(3),
        revenue:  r.total_revenue.to_f.round(2),
        invoices: r.invoice_count.to_i
      }
    end
  end

  # ── Tab 4: Low Stock Alert ────────────────────────────────────────────────
  def load_low_stock
    @threshold = params[:threshold].presence&.to_f || 10.0

    all_levels = StockLevel
                   .for_org(@organisation.id)
                   .joins(product: [:brand, :product_category])
                   .includes(product: [:brand, :product_category, :base_uom])
                   .order('brands.name, products.description')
                   .to_a

    @total_products = all_levels.count
    low = all_levels.select { |l| l.quantity <= @threshold }

    @out_of_stock_count = low.count { |l| l.quantity <= 0 }
    @critical_count     = low.count { |l| l.quantity > 0 && l.quantity <= (@threshold / 2) }
    @low_count          = low.count { |l| l.quantity > (@threshold / 2) && l.quantity <= @threshold }

    # By category for bar chart
    by_cat = low.group_by { |l| l.product.product_category.name }
    @chart_labels = by_cat.keys
    @chart_data   = by_cat.values.map(&:count)

    @rows = low.sort_by { |l| l.quantity }.map do |l|
      status = if l.quantity <= 0
                 'out_of_stock'
               elsif l.quantity <= (@threshold / 2)
                 'critical'
               else
                 'low'
               end
      {
        brand:    l.product.brand&.name || '—',
        category: l.product.product_category&.name || '—',
        product:  l.product.description,
        code:     l.product.full_code,
        quantity: l.quantity.to_f,
        uom:      l.product.base_uom&.short_name || '—',
        avg_cost: l.avg_cost.to_f,
        value:    l.stock_value,
        status:   status
      }
    end
  end

  def truncate_label(str, max = 22)
    str.length > max ? "#{str[0, max - 1]}…" : str
  end

end
