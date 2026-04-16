# app/controllers/reports/sales_controller.rb
class Reports::SalesController < Reports::BaseController

  before_action :set_active_tab

  # GET /reports/sales  (default → summary tab)
  # GET /reports/sales?tab=summary|by_customer|by_product|by_category|overdue
  def index
    case @tab
    when 'by_customer'  then load_by_customer
    when 'by_product'   then load_by_product
    when 'by_category'  then load_by_category
    when 'overdue'      then load_overdue
    else                     load_summary
    end
  end

  # Excel downloads — one action per tab
  def export
    case params[:tab]
    when 'summary'      then export_summary
    when 'by_customer'  then export_by_customer
    when 'by_product'   then export_by_product
    when 'by_category'  then export_by_category
    when 'overdue'      then export_overdue
    else
      redirect_to reports_sales_path, alert: 'Unknown export type.'
    end
  end

  private

  def set_active_tab
    @tab = params[:tab].presence || 'summary'
  end

  # ── Tab 1: Sales Summary ──────────────────────────────────────────────────
  def load_summary
    invoices = confirmed_sales.includes(:sale_payments)

    @total_revenue   = invoices.sum(:total_amount).to_f.round(2)
    @total_taxable   = invoices.sum(:total_taxable_amount).to_f.round(2)
    @total_tax       = invoices.sum(:total_tax_amount).to_f.round(2)
    @invoice_count   = invoices.count
    @avg_invoice     = @invoice_count > 0 ? (@total_revenue / @invoice_count).round(2) : 0
    @total_collected = invoices.joins(:sale_payments).sum('sale_payments.amount').to_f.round(2)
    @total_outstanding = (@total_revenue - @total_collected).round(2)

    # Daily chart data — group by date
    daily = invoices.group("DATE(invoice_date)").sum(:total_amount)
    @chart_labels = daily.keys.map { |d| d.strftime('%d %b') }
    @chart_data   = daily.values.map { |v| v.to_f.round(2) }

    # Breakdown by group (day/week/month based on range length)
    days = (@date_to - @date_from).to_i + 1
    if days <= 31
      @group_by   = 'day'
      @breakdown  = invoices.group("DATE(invoice_date)")
                             .select("DATE(invoice_date) as period,
                                      COUNT(*) as inv_count,
                                      SUM(total_amount) as revenue,
                                      SUM(total_tax_amount) as tax_total")
                             .order("period")
    elsif days <= 90
      @group_by   = 'week'
      @breakdown  = invoices.group("DATE_TRUNC('week', invoice_date)")
                             .select("DATE_TRUNC('week', invoice_date) as period,
                                      COUNT(*) as inv_count,
                                      SUM(total_amount) as revenue,
                                      SUM(total_tax_amount) as tax_total")
                             .order("period")
    else
      @group_by   = 'month'
      @breakdown  = invoices.group("DATE_TRUNC('month', invoice_date)")
                             .select("DATE_TRUNC('month', invoice_date) as period,
                                      COUNT(*) as inv_count,
                                      SUM(total_amount) as revenue,
                                      SUM(total_tax_amount) as tax_total")
                             .order("period")
    end
  end

  # ── Tab 2: Sales by Customer ──────────────────────────────────────────────
  def load_by_customer
    invoices = confirmed_sales.includes(:customer, :sale_payments)

    by_customer = invoices.group_by { |i| i.customer_id }

    @rows = by_customer.map do |cid, invs|
      customer   = invs.first.customer
      invoiced   = invs.sum { |i| i.total_amount.to_f }.round(2)
      paid       = invs.sum { |i| i.total_paid.to_f }.round(2)
      outstanding = (invoiced - paid).round(2)
      tax_total  = invs.sum { |i| i.total_tax_amount.to_f }.round(2)
      {
        customer:    customer,
        name:        customer&.name || 'Walk-in Customer',
        gstin:       customer&.gstin,
        inv_count:   invs.size,
        invoiced:    invoiced,
        paid:        paid,
        outstanding: outstanding,
        tax_total:   tax_total,
        last_sale:   invs.map(&:invoice_date).compact.max
      }
    end.sort_by { |r| -r[:invoiced] }

    # Top 5 chart
    top5 = @rows.first(5)
    @chart_labels = top5.map { |r| r[:name].truncate(20) }
    @chart_data   = top5.map { |r| r[:invoiced] }
    @total_revenue = @rows.sum { |r| r[:invoiced] }.round(2)
  end

  # ── Tab 3: Sales by Product ───────────────────────────────────────────────
  def load_by_product
    items = SalesInvoiceItem
              .joins(:sales_invoice, :product)
              .where(
                sales_invoices: { organisation_id: @organisation.id, status: 'confirmed' },
                'sales_invoices.invoice_date' => @date_from..@date_to
              )
              .where.not(product_id: nil)
              .where(line_type: %w[product paint])
              .group(:product_id)
              .select(
                "sales_invoice_items.product_id,
                 SUM(sales_invoice_items.quantity) as total_qty,
                 SUM(sales_invoice_items.total_amount) as total_revenue,
                 SUM(sales_invoice_items.taxable_amount) as total_taxable,
                 SUM(sales_invoice_items.tax_amount) as total_tax,
                 COUNT(DISTINCT sales_invoice_items.sales_invoice_id) as invoice_count"
              )
              .order("total_revenue DESC")

    product_ids = items.map(&:product_id)
    products    = Product.includes(:brand, :base_uom, :product_category)
                         .where(id: product_ids)
                         .index_by(&:id)

    @rows = items.map do |row|
      product = products[row.product_id]
      {
        product:       product,
        name:          product&.description || "Product ##{row.product_id}",
        brand:         product&.brand&.name,
        category:      product&.product_category&.name,
        uom:           product&.base_uom&.short_name,
        total_qty:     row.total_qty.to_f,
        total_revenue: row.total_revenue.to_f.round(2),
        total_taxable: row.total_taxable.to_f.round(2),
        total_tax:     row.total_tax.to_f.round(2),
        invoice_count: row.invoice_count.to_i
      }
    end

    top5 = @rows.first(5)
    @chart_labels = top5.map { |r| r[:name].truncate(25) }
    @chart_data   = top5.map { |r| r[:total_revenue] }
    @total_revenue = @rows.sum { |r| r[:total_revenue] }.round(2)
  end

  # ── Tab 4: Sales by Category & Brand ─────────────────────────────────────
  def load_by_category
    items = SalesInvoiceItem
              .joins(:sales_invoice, product: [:product_category, :brand])
              .where(
                sales_invoices: { organisation_id: @organisation.id, status: 'confirmed' },
                'sales_invoices.invoice_date' => @date_from..@date_to
              )
              .where.not(product_id: nil)
              .where(line_type: %w[product paint])

    # Group by category → brand
    by_cat_brand = {}
    items.each do |item|
      cat   = item.product&.product_category&.name || 'Uncategorised'
      brand = item.product&.brand&.name || 'No Brand'
      key   = [cat, brand]
      by_cat_brand[key] ||= { revenue: 0, tax: 0, qty: 0, count: 0 }
      by_cat_brand[key][:revenue] += item.total_amount.to_f
      by_cat_brand[key][:tax]     += item.tax_amount.to_f
      by_cat_brand[key][:qty]     += item.quantity.to_f
      by_cat_brand[key][:count]   += 1
    end

    # Structure as nested hash: category → [brands]
    @categories = {}
    by_cat_brand.each do |(cat, brand), data|
      @categories[cat] ||= { brands: [], total: 0, tax: 0 }
      @categories[cat][:brands] << {
        brand:   brand,
        revenue: data[:revenue].round(2),
        tax:     data[:tax].round(2),
        qty:     data[:qty].round(2),
        count:   data[:count]
      }
      @categories[cat][:total] += data[:revenue]
      @categories[cat][:tax]   += data[:tax]
    end
    @categories.each { |_, v| v[:brands].sort_by! { |b| -b[:revenue] } }
    @categories = @categories.sort_by { |_, v| -v[:total] }.to_h

    # Chart by category
    @chart_labels = @categories.keys
    @chart_data   = @categories.values.map { |v| v[:total].round(2) }
    @total_revenue = @chart_data.sum.round(2)
  end

  # ── Tab 5: Overdue Receivables (Ageing) ───────────────────────────────────
  def load_overdue
    # For ageing we ignore the date filter — show all outstanding as of today
    invoices = SalesInvoice
                 .for_org(@organisation.id)
                 .confirmed
                 .where.not(customer_id: nil)
                 .where('payment_due_date < ?', Date.today)
                 .includes(:customer, :sale_payments)

    @rows = invoices.filter_map do |inv|
      outstanding = inv.outstanding_amount.to_f
      next if outstanding <= 0
      days_overdue = (Date.today - inv.payment_due_date).to_i
      bucket = case days_overdue
               when 0..30   then '0–30 days'
               when 31..60  then '31–60 days'
               when 61..90  then '61–90 days'
               else              '90+ days'
               end
      {
        invoice:      inv,
        customer:     inv.customer,
        days_overdue: days_overdue,
        bucket:       bucket,
        outstanding:  outstanding,
        invoice_date: inv.invoice_date,
        due_date:     inv.payment_due_date
      }
    end.sort_by { |r| -r[:days_overdue] }

    # Bucket totals
    @buckets = @rows.group_by { |r| r[:bucket] }
    @bucket_totals = @buckets.transform_values { |rows| rows.sum { |r| r[:outstanding] }.round(2) }
    @total_overdue = @rows.sum { |r| r[:outstanding] }.round(2)

    # Chart
    bucket_order = ['0–30 days', '31–60 days', '61–90 days', '90+ days']
    @chart_labels = bucket_order
    @chart_data   = bucket_order.map { |b| @bucket_totals[b].to_f.round(2) }
  end

  # ── Excel exports ─────────────────────────────────────────────────────────
  def export_summary
    load_summary
    package = Axlsx::Package.new
    wb = package.workbook
    add_styles(wb)
    sheet = wb.add_worksheet(name: 'Sales Summary')

    sheet.add_row ["Sales Summary Report — #{@period_label}"], style: wb.styles.add_style(b: true, sz: 14)
    sheet.add_row []
    sheet.add_row ['Period', 'Invoices', 'Revenue (₹)', 'Tax (₹)', 'Collected (₹)', 'Outstanding (₹)']
    @breakdown.each do |row|
      label = case @group_by
              when 'day'   then row.period.strftime('%d %b %Y')
              when 'week'  then "Week of #{row.period.strftime('%d %b %Y')}"
              else              row.period.strftime('%b %Y')
              end
      sheet.add_row [label, row.inv_count, row.revenue.to_f.round(2),
                     row.tax_total.to_f.round(2), '', '']
    end
    send_xlsx(package, "sales_summary_#{@date_from.iso8601}")
  end

  def export_by_customer
    load_by_customer
    package = Axlsx::Package.new
    wb = package.workbook
    sheet = wb.add_worksheet(name: 'Sales by Customer')
    sheet.add_row ["Sales by Customer — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Customer', 'GSTIN', 'Invoices', 'Invoiced (₹)', 'Paid (₹)', 'Outstanding (₹)', 'Last Sale']
    @rows.each do |r|
      sheet.add_row [r[:name], r[:gstin].presence || '—', r[:inv_count],
                     r[:invoiced], r[:paid], r[:outstanding],
                     r[:last_sale]&.strftime('%d %b %Y')]
    end
    send_xlsx(package, "sales_by_customer_#{@date_from.iso8601}")
  end

  def export_by_product
    load_by_product
    package = Axlsx::Package.new
    wb = package.workbook
    sheet = wb.add_worksheet(name: 'Sales by Product')
    sheet.add_row ["Sales by Product — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Product', 'Brand', 'Category', 'UOM', 'Qty Sold', 'Revenue (₹)', 'Tax (₹)', 'Invoices']
    @rows.each do |r|
      sheet.add_row [r[:name], r[:brand].presence || '—', r[:category].presence || '—',
                     r[:uom].presence || '—', r[:total_qty], r[:total_revenue],
                     r[:total_tax], r[:invoice_count]]
    end
    send_xlsx(package, "sales_by_product_#{@date_from.iso8601}")
  end

  def export_by_category
    load_by_category
    package = Axlsx::Package.new
    wb = package.workbook
    sheet = wb.add_worksheet(name: 'Sales by Category')
    sheet.add_row ["Sales by Category & Brand — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Category', 'Brand', 'Revenue (₹)', 'Tax (₹)', 'Qty', 'Transactions']
    @categories.each do |cat, data|
      data[:brands].each do |b|
        sheet.add_row [cat, b[:brand], b[:revenue], b[:tax], b[:qty], b[:count]]
      end
    end
    send_xlsx(package, "sales_by_category_#{@date_from.iso8601}")
  end

  def export_overdue
    load_overdue
    package = Axlsx::Package.new
    wb = package.workbook
    sheet = wb.add_worksheet(name: 'Overdue Receivables')
    sheet.add_row ["Overdue Receivables — As of #{Date.today.strftime('%d %b %Y')}"]
    sheet.add_row []
    sheet.add_row ['Customer', 'Invoice', 'Invoice Date', 'Due Date', 'Days Overdue', 'Bucket', 'Outstanding (₹)']
    @rows.each do |r|
      sheet.add_row [r[:customer]&.name, r[:invoice].display_number,
                     r[:invoice_date]&.strftime('%d %b %Y'),
                     r[:due_date]&.strftime('%d %b %Y'),
                     r[:days_overdue], r[:bucket], r[:outstanding]]
    end
    send_xlsx(package, "overdue_receivables_#{Date.today.iso8601}")
  end

  def send_xlsx(package, filename)
    temp = Tempfile.new(["report_", ".xlsx"])
    package.serialize(temp.path)
    send_file temp.path,
              filename:    "#{filename}.xlsx",
              type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  def add_styles(wb)
    wb.styles.add_style(b: true, sz: 12, fg_color: 'FFFFFF', bg_color: '1e3a6e')
  end

end