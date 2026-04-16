# app/controllers/reports/purchases_controller.rb
class Reports::PurchasesController < Reports::BaseController

  before_action :set_active_tab

  # GET /reports/purchases
  def index
    case @tab
    when 'by_supplier' then load_by_supplier
    when 'by_product'  then load_by_product
    when 'overdue'     then load_overdue
    else                    load_summary
    end
  end

  def export
    case params[:tab]
    when 'summary'     then export_summary
    when 'by_supplier' then export_by_supplier
    when 'by_product'  then export_by_product
    when 'overdue'     then export_overdue
    else
      redirect_to reports_purchases_path, alert: 'Unknown export type.'
    end
  end

  private

  def set_active_tab
    @tab = params[:tab].presence || 'summary'
  end

  # ── Tab 1: Purchase Summary ───────────────────────────────────────────────
  def load_summary
    invoices = confirmed_purchases.includes(:purchase_payments)

    @total_spend       = invoices.sum(:total_amount).to_f.round(2)
    @total_taxable     = invoices.sum(:total_taxable_amount).to_f.round(2)
    @total_tax         = invoices.sum(:total_tax_amount).to_f.round(2)
    @invoice_count     = invoices.count
    @avg_invoice       = @invoice_count > 0 ? (@total_spend / @invoice_count).round(2) : 0
    @total_paid        = invoices.joins(:purchase_payments).sum('purchase_payments.amount').to_f.round(2)
    @total_outstanding = (@total_spend - @total_paid).round(2)

    daily = invoices.group("DATE(invoice_date)").sum(:total_amount)
    @chart_labels = daily.keys.map { |d| d.strftime('%d %b') }
    @chart_data   = daily.values.map { |v| v.to_f.round(2) }

    days = (@date_to - @date_from).to_i + 1
    if days <= 31
      @group_by  = 'day'
      @breakdown = invoices.group("DATE(invoice_date)")
                           .select("DATE(invoice_date) as period,
                                    COUNT(*) as inv_count,
                                    SUM(total_amount) as spend,
                                    SUM(total_tax_amount) as tax_total")
                           .order("period")
    elsif days <= 90
      @group_by  = 'week'
      @breakdown = invoices.group("DATE_TRUNC('week', invoice_date)")
                           .select("DATE_TRUNC('week', invoice_date) as period,
                                    COUNT(*) as inv_count,
                                    SUM(total_amount) as spend,
                                    SUM(total_tax_amount) as tax_total")
                           .order("period")
    else
      @group_by  = 'month'
      @breakdown = invoices.group("DATE_TRUNC('month', invoice_date)")
                           .select("DATE_TRUNC('month', invoice_date) as period,
                                    COUNT(*) as inv_count,
                                    SUM(total_amount) as spend,
                                    SUM(total_tax_amount) as tax_total")
                           .order("period")
    end
  end

  # ── Tab 2: Purchase by Supplier ───────────────────────────────────────────
  def load_by_supplier
    invoices = confirmed_purchases.includes(:supplier, :purchase_payments)

    by_supplier = invoices.group_by(&:supplier_id)

    @rows = by_supplier.map do |_sid, invs|
      supplier    = invs.first.supplier
      invoiced    = invs.sum { |i| i.total_amount.to_f }.round(2)
      paid        = invs.sum { |i| i.total_paid.to_f }.round(2)
      outstanding = (invoiced - paid).round(2)
      tax_total   = invs.sum { |i| i.total_tax_amount.to_f }.round(2)
      {
        supplier:      supplier,
        name:          supplier&.name || 'Unknown Supplier',
        gstin:         supplier&.gstin,
        inv_count:     invs.size,
        invoiced:      invoiced,
        paid:          paid,
        outstanding:   outstanding,
        tax_total:     tax_total,
        last_purchase: invs.map(&:invoice_date).compact.max
      }
    end.sort_by { |r| -r[:invoiced] }

    top5 = @rows.first(5)
    @chart_labels = top5.map { |r| r[:name].truncate(20) }
    @chart_data   = top5.map { |r| r[:invoiced] }
    @total_spend  = @rows.sum { |r| r[:invoiced] }.round(2)
  end

  # ── Tab 3: Purchase by Product ────────────────────────────────────────────
  def load_by_product
    items = PurchaseInvoiceItem
              .joins(:purchase_invoice, :product)
              .where(
                purchase_invoices: { organisation_id: @organisation.id, status: 'confirmed' },
                'purchase_invoices.invoice_date' => @date_from..@date_to
              )
              .where.not(product_id: nil)
              .group(:product_id)
              .select(
                "purchase_invoice_items.product_id,
                 SUM(purchase_invoice_items.quantity) as total_qty,
                 SUM(purchase_invoice_items.total_amount) as total_cost,
                 SUM(purchase_invoice_items.taxable_amount) as total_taxable,
                 SUM(purchase_invoice_items.tax_amount) as total_tax,
                 COUNT(DISTINCT purchase_invoice_items.purchase_invoice_id) as invoice_count"
              )
              .order("total_cost DESC")

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
        total_cost:    row.total_cost.to_f.round(2),
        total_taxable: row.total_taxable.to_f.round(2),
        total_tax:     row.total_tax.to_f.round(2),
        invoice_count: row.invoice_count.to_i
      }
    end

    top5 = @rows.first(5)
    @chart_labels = top5.map { |r| r[:name].truncate(25) }
    @chart_data   = top5.map { |r| r[:total_cost] }
    @total_spend  = @rows.sum { |r| r[:total_cost] }.round(2)
  end

  # ── Tab 4: Overdue Payables (Ageing) ──────────────────────────────────────
  def load_overdue
    invoices = PurchaseInvoice
                 .for_org(@organisation.id)
                 .confirmed
                 .where.not(supplier_id: nil)
                 .where('payment_due_date < ?', Date.today)
                 .includes(:supplier, :purchase_payments)

    @rows = invoices.filter_map do |inv|
      outstanding = inv.outstanding_amount.to_f
      next if outstanding <= 0
      days_overdue = (Date.today - inv.payment_due_date).to_i
      bucket = case days_overdue
               when 0..30  then '0–30 days'
               when 31..60 then '31–60 days'
               when 61..90 then '61–90 days'
               else             '90+ days'
               end
      {
        invoice:      inv,
        supplier:     inv.supplier,
        days_overdue: days_overdue,
        bucket:       bucket,
        outstanding:  outstanding,
        invoice_date: inv.invoice_date,
        due_date:     inv.payment_due_date
      }
    end.sort_by { |r| -r[:days_overdue] }

    @buckets       = @rows.group_by { |r| r[:bucket] }
    @bucket_totals = @buckets.transform_values { |rows| rows.sum { |r| r[:outstanding] }.round(2) }
    @total_overdue = @rows.sum { |r| r[:outstanding] }.round(2)

    bucket_order  = ['0–30 days', '31–60 days', '61–90 days', '90+ days']
    @chart_labels = bucket_order
    @chart_data   = bucket_order.map { |b| @bucket_totals[b].to_f.round(2) }
  end

  # ── Excel Exports ─────────────────────────────────────────────────────────
  def export_summary
    load_summary
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Purchase Summary')
    sheet.add_row ["Purchase Summary Report — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Period', 'Invoices', 'Spend (₹)', 'Tax (₹)', 'Taxable (₹)']
    @breakdown.each do |row|
      label = case @group_by
              when 'day'  then row.period.strftime('%d %b %Y')
              when 'week' then "Week of #{row.period.strftime('%d %b %Y')}"
              else             row.period.strftime('%b %Y')
              end
      sheet.add_row [label, row.inv_count, row.spend.to_f.round(2),
                     row.tax_total.to_f.round(2),
                     (row.spend.to_f - row.tax_total.to_f).round(2)]
    end
    send_xlsx(package, "purchase_summary_#{@date_from.iso8601}")
  end

  def export_by_supplier
    load_by_supplier
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Purchase by Supplier')
    sheet.add_row ["Purchase by Supplier — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Supplier', 'GSTIN', 'Invoices', 'Invoiced (₹)', 'Paid (₹)', 'Outstanding (₹)', 'Last Purchase']
    @rows.each do |r|
      sheet.add_row [r[:name], r[:gstin].presence || '—', r[:inv_count],
                     r[:invoiced], r[:paid], r[:outstanding],
                     r[:last_purchase]&.strftime('%d %b %Y')]
    end
    send_xlsx(package, "purchase_by_supplier_#{@date_from.iso8601}")
  end

  def export_by_product
    load_by_product
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Purchase by Product')
    sheet.add_row ["Purchase by Product — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Product', 'Brand', 'Category', 'UOM', 'Qty Ordered', 'Cost (₹)', 'Tax (₹)', 'Invoices']
    @rows.each do |r|
      sheet.add_row [r[:name], r[:brand].presence || '—', r[:category].presence || '—',
                     r[:uom].presence || '—', r[:total_qty], r[:total_cost],
                     r[:total_tax], r[:invoice_count]]
    end
    send_xlsx(package, "purchase_by_product_#{@date_from.iso8601}")
  end

  def export_overdue
    load_overdue
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Overdue Payables')
    sheet.add_row ["Overdue Payables — As of #{Date.today.strftime('%d %b %Y')}"]
    sheet.add_row []
    sheet.add_row ['Supplier', 'Invoice', 'Invoice Date', 'Due Date', 'Days Overdue', 'Bucket', 'Outstanding (₹)']
    @rows.each do |r|
      sheet.add_row [r[:supplier]&.name, r[:invoice].display_number,
                     r[:invoice_date]&.strftime('%d %b %Y'),
                     r[:due_date]&.strftime('%d %b %Y'),
                     r[:days_overdue], r[:bucket], r[:outstanding]]
    end
    send_xlsx(package, "overdue_payables_#{Date.today.iso8601}")
  end

  def send_xlsx(package, filename)
    temp = Tempfile.new(['report_', '.xlsx'])
    package.serialize(temp.path)
    send_file temp.path,
              filename:    "#{filename}.xlsx",
              type:        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

end
