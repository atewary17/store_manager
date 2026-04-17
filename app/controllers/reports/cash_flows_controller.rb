# app/controllers/reports/cash_flows_controller.rb
class Reports::CashFlowsController < Reports::BaseController

  before_action :set_active_tab

  # GET /reports/cash_flows
  def index
    case @tab
    when 'outflow'   then load_outflow
    when 'net'       then load_net
    else                  load_inflow
    end
  end

  def export
    case params[:tab]
    when 'inflow'  then export_inflow
    when 'outflow' then export_outflow
    when 'net'     then export_net
    else
      redirect_to reports_cash_flows_path, alert: 'Unknown export type.'
    end
  end

  private

  def set_active_tab
    @tab = params[:tab].presence || 'inflow'
  end

  # ── Tab 1: Inflow — Payments Received ────────────────────────────────────
  def load_inflow
    payments = SalePayment
                 .for_org(@organisation.id)
                 .where(payment_date: @date_from..@date_to)
                 .includes(:sales_invoice, :customer)

    @total_inflow = payments.sum(:amount).to_f.round(2)
    @txn_count    = payments.count

    # By payment mode
    by_mode = payments.group(:payment_mode).sum(:amount)
    @by_mode = by_mode.transform_values { |v| v.to_f.round(2) }
                      .sort_by { |_, v| -v }.to_h

    # Daily totals for chart
    daily = payments.group("DATE(payment_date)").sum(:amount)
    @chart_labels = daily.keys.map { |d| d.strftime('%d %b') }
    @chart_data   = daily.values.map { |v| v.to_f.round(2) }

    # Mode breakdown for donut
    @mode_labels = @by_mode.keys.map { |m| m.titleize }
    @mode_data   = @by_mode.values

    # Rows for table
    @rows = payments.order(payment_date: :desc).map do |p|
      {
        date:     p.payment_date,
        receipt:  p.receipt_label,
        customer: p.customer&.name || 'Walk-in',
        invoice:  p.sales_invoice&.display_number,
        mode:     p.payment_mode,
        amount:   p.amount.to_f.round(2)
      }
    end
  end

  # ── Tab 2: Outflow — Payments Made ───────────────────────────────────────
  def load_outflow
    payments = PurchasePayment
                 .for_org(@organisation.id)
                 .where(payment_date: @date_from..@date_to)
                 .includes(:purchase_invoice, :supplier)

    @total_outflow = payments.sum(:amount).to_f.round(2)
    @txn_count     = payments.count

    by_mode = payments.group(:payment_mode).sum(:amount)
    @by_mode = by_mode.transform_values { |v| v.to_f.round(2) }
                      .sort_by { |_, v| -v }.to_h

    daily = payments.group("DATE(payment_date)").sum(:amount)
    @chart_labels = daily.keys.map { |d| d.strftime('%d %b') }
    @chart_data   = daily.values.map { |v| v.to_f.round(2) }

    @mode_labels = @by_mode.keys.map { |m| m.titleize }
    @mode_data   = @by_mode.values

    @rows = payments.order(payment_date: :desc).map do |p|
      {
        date:     p.payment_date,
        ref:      p.payment_label,
        supplier: p.supplier&.name || '—',
        invoice:  p.purchase_invoice&.display_number,
        mode:     p.payment_mode,
        amount:   p.amount.to_f.round(2)
      }
    end
  end

  # ── Tab 3: Net Cash Flow ──────────────────────────────────────────────────
  def load_net
    inflows  = SalePayment.for_org(@organisation.id)
                           .where(payment_date: @date_from..@date_to)
    outflows = PurchasePayment.for_org(@organisation.id)
                              .where(payment_date: @date_from..@date_to)

    @total_inflow  = inflows.sum(:amount).to_f.round(2)
    @total_outflow = outflows.sum(:amount).to_f.round(2)
    @net_flow      = (@total_inflow - @total_outflow).round(2)

    # Build a merged daily timeline
    daily_in  = inflows.group("DATE(payment_date)").sum(:amount)
                       .transform_values { |v| v.to_f.round(2) }
    daily_out = outflows.group("DATE(payment_date)").sum(:amount)
                        .transform_values { |v| v.to_f.round(2) }

    all_dates = (daily_in.keys + daily_out.keys).uniq.sort
    @chart_labels  = all_dates.map { |d| d.strftime('%d %b') }
    @chart_inflow  = all_dates.map { |d| daily_in[d]  || 0 }
    @chart_outflow = all_dates.map { |d| daily_out[d] || 0 }
    @chart_net     = all_dates.map.with_index { |d, i| (@chart_inflow[i] - @chart_outflow[i]).round(2) }

    # Monthly summary table
    months = (daily_in.keys + daily_out.keys).uniq
               .map { |d| Date.new(d.year, d.month, 1) }.uniq.sort

    @monthly = months.map do |m|
      m_in  = inflows.where("DATE_TRUNC('month', payment_date) = ?", m).sum(:amount).to_f.round(2)
      m_out = outflows.where("DATE_TRUNC('month', payment_date) = ?", m).sum(:amount).to_f.round(2)
      { month: m, inflow: m_in, outflow: m_out, net: (m_in - m_out).round(2) }
    end
  end

  # ── Exports ───────────────────────────────────────────────────────────────
  def export_inflow
    load_inflow
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Payments Received')
    sheet.add_row ["Payments Received — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Date', 'Receipt #', 'Customer', 'Invoice', 'Mode', 'Amount (₹)']
    @rows.each do |r|
      sheet.add_row [r[:date]&.strftime('%d %b %Y'), r[:receipt], r[:customer],
                     r[:invoice], r[:mode]&.titleize, r[:amount]]
    end
    sheet.add_row []
    sheet.add_row ['', '', '', '', 'TOTAL', @total_inflow]
    send_xlsx(package, "payments_received_#{@date_from.iso8601}")
  end

  def export_outflow
    load_outflow
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Payments Made')
    sheet.add_row ["Payments Made — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Date', 'Reference #', 'Supplier', 'Invoice', 'Mode', 'Amount (₹)']
    @rows.each do |r|
      sheet.add_row [r[:date]&.strftime('%d %b %Y'), r[:ref], r[:supplier],
                     r[:invoice], r[:mode]&.titleize, r[:amount]]
    end
    sheet.add_row []
    sheet.add_row ['', '', '', '', 'TOTAL', @total_outflow]
    send_xlsx(package, "payments_made_#{@date_from.iso8601}")
  end

  def export_net
    load_net
    package = Axlsx::Package.new
    wb      = package.workbook
    sheet   = wb.add_worksheet(name: 'Net Cash Flow')
    sheet.add_row ["Net Cash Flow — #{@period_label}"]
    sheet.add_row []
    sheet.add_row ['Month', 'Inflow (₹)', 'Outflow (₹)', 'Net (₹)']
    @monthly.each do |r|
      sheet.add_row [r[:month].strftime('%B %Y'), r[:inflow], r[:outflow], r[:net]]
    end
    sheet.add_row []
    sheet.add_row ['TOTAL', @total_inflow, @total_outflow, @net_flow]
    send_xlsx(package, "net_cash_flow_#{@date_from.iso8601}")
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
