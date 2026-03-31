# app/controllers/accounting/gst_reports_controller.rb
#
# GST Reports for Indian hardware/paint stores.
#
# GSTR-1  : Outward supplies (sales) — filed monthly/quarterly
# GSTR-3B : Summary return — net tax payable after ITC set-off
# ITC     : Input Tax Credit register from purchases
# HSN     : HSN-wise summary (mandatory for turnover > ₹5 Cr)
#
class Accounting::GstReportsController < Accounting::BaseController

  before_action :set_period

  # GET /accounting/gst
  def index
    # Quick summary cards for the selected period
    @output   = output_tax_summary
    @input    = input_tax_summary
    @net_gst  = net_gst_payable(@output, @input)
  end

  # GET /accounting/gst/gstr1
  # Outward supplies — sales invoices
  def gstr1
    base = confirmed_sales.includes(:customer, sales_invoice_items: :product)

    # B2B: Sales to registered businesses (customer has GSTIN)
    @b2b = base.joins(:customer).where.not(customers: { gstin: [nil, ''] })
               .order(:invoice_date)

    # B2C: Sales to unregistered customers or walk-ins
    @b2c = base.where(
      "NOT EXISTS (SELECT 1 FROM customers c WHERE c.id = sales_invoices.customer_id AND c.gstin IS NOT NULL AND c.gstin != '')"
    ).order(:invoice_date)

    # HSN summary for GSTR-1 Table 12
    @hsn_summary = gstr1_hsn_summary

    @totals = {
      taxable:  (@b2b + @b2c).sum(&:total_taxable_amount),
      tax:      (@b2b + @b2c).sum(&:total_tax_amount),
      invoices: (@b2b + @b2c).count
    }
  end

  # GET /accounting/gst/gstr3b
  # Summary return — net liability after ITC set-off
  def gstr3b
    @output = output_tax_summary
    @input  = input_tax_summary

    # ── Opening balance: ITC carried forward from prior month ─────────────
    # Fetched from GstCreditLedgerEntry (persisted when a period is closed).
    # Falls back to { igst: 0, cgst: 0, sgst: 0 } if no prior entry exists
    # (i.e. first month of use).
    @opening = GstCreditLedgerEntry.opening_balance_for(
      organisation_id: @organisation.id,
      year:  @period_year,
      month: @period_month
    )

    # ── Total ITC available = opening carry-forward + current period ITC ──
    # This is what the GST portal calls "Total ITC Available".
    total_igst_itc = (@opening[:igst] + @input[:igst]).round(2)
    total_cgst_itc = (@opening[:cgst] + @input[:cgst]).round(2)
    total_sgst_itc = (@opening[:sgst] + @input[:sgst]).round(2)

    @opening_total = (@opening[:igst] + @opening[:cgst] + @opening[:sgst]).round(2)

    # ── Run 7-step ITC set-off (shared with close_period) ────────────────
    result = run_itc_setoff(output: @output, input: @input, opening: @opening)

    @igst_payable  = result[:igst_payable]
    @cgst_payable  = result[:cgst_payable]
    @sgst_payable  = result[:sgst_payable]
    @total_payable = (@igst_payable + @cgst_payable + @sgst_payable).round(2)

    # ── Closing balances = carry-forward to next month ────────────────────
    @igst_credit  = result[:igst_credit]
    @cgst_credit  = result[:cgst_credit]
    @sgst_credit  = result[:sgst_credit]
    @total_credit = (@igst_credit + @cgst_credit + @sgst_credit).round(2)

    # ── Fetch or build this period's ledger entry (for Close Period button) ─
    @ledger_entry = GstCreditLedgerEntry.find_or_build(
      organisation_id: @organisation.id,
      year:  @period_year,
      month: @period_month
    )

    # ── Detailed utilisation for Section 5.1 table ────────────────────────
    @itc_utilisation = result[:utilisation]

    # Invoices breakdown
    @sales_invoices    = confirmed_sales.includes(:customer)
    @purchase_invoices = confirmed_purchases.includes(:supplier)
  end

  # GET /accounting/gst/itc
  # Input Tax Credit register — purchase invoices
  def itc
    @items = PurchaseInvoiceItem
               .joins(:purchase_invoice, :product)
               .where(purchase_invoices: { organisation_id: @organisation.id, status: 'confirmed' })
               .where(purchase_invoices: { invoice_date: @period_start..@period_end })
               .where('purchase_invoice_items.tax_amount > 0')
               .includes(purchase_invoice: :supplier, product: :product_category)
               .order('purchase_invoices.invoice_date ASC')

    @total_itc_cgst = @items.sum { |i| i.cgst_amount }
    @total_itc_sgst = @items.sum { |i| i.sgst_amount }
    @total_itc_igst = @items.sum { |i| i.igst_amount }
    @total_itc      = @items.sum(&:tax_amount)

    # Group by GST rate for summary
    @by_rate = @items.group_by(&:gst_rate).transform_values do |items|
      {
        taxable: items.sum(&:taxable_amount),
        tax:     items.sum(&:tax_amount),
        count:   items.count
      }
    end.sort_by { |rate, _| rate }
  end

  # GET /accounting/gst/hsn
  # HSN-wise summary (sales + purchases)
  def hsn
    # Sales HSN summary — use raw SQL to avoid ActiveRecord complaining about
    # missing model attributes when using a custom SELECT with aggregates.
    sales_sql = <<~SQL
      SELECT
        p2.hsn_code,
        sales_invoice_items.gst_rate,
        COUNT(DISTINCT sales_invoices.id)             AS invoice_count,
        SUM(sales_invoice_items.quantity)             AS total_qty,
        SUM(sales_invoice_items.taxable_amount)       AS total_taxable,
        SUM(sales_invoice_items.tax_amount)           AS total_tax
      FROM sales_invoice_items
      JOIN sales_invoices ON sales_invoices.id = sales_invoice_items.sales_invoice_id
      JOIN products p2    ON p2.id = sales_invoice_items.product_id
      WHERE sales_invoices.organisation_id = #{@organisation.id}
        AND sales_invoices.status = 'confirmed'
        AND sales_invoices.invoice_date BETWEEN '#{@period_start}' AND '#{@period_end}'
      GROUP BY p2.hsn_code, sales_invoice_items.gst_rate
      ORDER BY p2.hsn_code
    SQL
    @sales_hsn = ActiveRecord::Base.connection.exec_query(sales_sql).to_a

    # Purchase HSN summary
    purchase_sql = <<~SQL
      SELECT
        p3.hsn_code,
        purchase_invoice_items.gst_rate,
        COUNT(DISTINCT purchase_invoice_items.purchase_invoice_id) AS invoice_count,
        SUM(purchase_invoice_items.quantity)                       AS total_qty,
        SUM(purchase_invoice_items.taxable_amount)                 AS total_taxable,
        SUM(purchase_invoice_items.tax_amount)                     AS total_tax
      FROM purchase_invoice_items
      JOIN purchase_invoices ON purchase_invoices.id = purchase_invoice_items.purchase_invoice_id
      JOIN products p3       ON p3.id = purchase_invoice_items.product_id
      WHERE purchase_invoices.organisation_id = #{@organisation.id}
        AND purchase_invoices.status = 'confirmed'
        AND purchase_invoices.invoice_date BETWEEN '#{@period_start}' AND '#{@period_end}'
      GROUP BY p3.hsn_code, purchase_invoice_items.gst_rate
      ORDER BY p3.hsn_code
    SQL
    @purchase_hsn = ActiveRecord::Base.connection.exec_query(purchase_sql).to_a
  end

  # POST /accounting/gst/close_period
  # Persists the current period's closing ITC balances to the ledger.
  # Once closed, the next month's GSTR-3B will use these as its opening balance.
  def close_period
    year  = params[:year].to_i
    month = params[:month].to_i

    # Rebuild the full set-off calculation for this period to get accurate numbers
    @output = output_tax_summary_for(year: year, month: month)
    @input  = input_tax_summary_for(year: year, month: month)

    opening = GstCreditLedgerEntry.opening_balance_for(
      organisation_id: @organisation.id,
      year: year, month: month
    )

    # Run 7-step set-off
    result = run_itc_setoff(
      output: @output,
      input:  @input,
      opening: opening
    )

    entry = GstCreditLedgerEntry.find_or_build(
      organisation_id: @organisation.id,
      year: year, month: month
    )

    entry.assign_attributes(
      opening_igst:    opening[:igst],
      opening_cgst:    opening[:cgst],
      opening_sgst:    opening[:sgst],
      period_igst_itc: @input[:igst],
      period_cgst_itc: @input[:cgst],
      period_sgst_itc: @input[:sgst],
      period_igst_out: @output[:igst],
      period_cgst_out: @output[:cgst],
      period_sgst_out: @output[:sgst],
      closing_igst:    result[:igst_credit],
      closing_cgst:    result[:cgst_credit],
      closing_sgst:    result[:sgst_credit],
      cash_igst:       result[:igst_payable],
      cash_cgst:       result[:cgst_payable],
      cash_sgst:       result[:sgst_payable],
      period_closed:   true,
      closed_at:       Time.current,
      closed_by:       current_user
    )

    if entry.save
      redirect_to accounting_gstr3b_path(month: month, year: year),
        notice: "Period #{Date::MONTHNAMES[month]} #{year} closed. "                 "Carry-forward: IGST ₹#{result[:igst_credit]}, "                 "CGST ₹#{result[:cgst_credit]}, SGST ₹#{result[:sgst_credit]}."
    else
      redirect_to accounting_gstr3b_path(month: month, year: year),
        alert: "Could not close period: #{entry.errors.full_messages.join(', ')}"
    end
  end

  private

  # ── Period helpers ────────────────────────────────────────────────────────

  def set_period
    if params[:month].present? && params[:year].present?
      @period_month = params[:month].to_i
      @period_year  = params[:year].to_i
    else
      today = Date.today
      # GST filing is for the previous month after the 11th
      ref = today.day >= 11 ? today.prev_month : today.prev_month.prev_month
      @period_month = ref.month
      @period_year  = ref.year
    end

    @period_start = Date.new(@period_year, @period_month, 1)
    @period_end   = @period_start.end_of_month
    @period_label = @period_start.strftime('%B %Y')

    # Filing deadlines — computed once, available in all actions/views
    @gstr1_due  = gstr1_due_date
    @gstr3b_due = gstr3b_due_date

    # Build month options for the selector (last 12 months)
    @month_options = 12.times.map do |i|
      d = Date.today.beginning_of_month - i.months
      ["#{d.strftime('%b %Y')}", { month: d.month, year: d.year }]
    end
  end

  def confirmed_sales
    SalesInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(invoice_date: @period_start..@period_end)
  end

  def confirmed_purchases
    PurchaseInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(invoice_date: @period_start..@period_end)
  end

  # ── Tax summary builders ──────────────────────────────────────────────────

  def output_tax_summary
    items = SalesInvoiceItem
              .joins(:sales_invoice)
              .where(sales_invoices: { organisation_id: @organisation.id, status: 'confirmed' })
              .where(sales_invoices: { invoice_date: @period_start..@period_end })

    taxable = items.sum(:taxable_amount)
    tax     = items.sum(:tax_amount)

    # Read directly from proper columns (set by compute_amounts via state comparison)
    cgst = items.sum(:cgst_amount).round(2)
    sgst = items.sum(:sgst_amount).round(2)
    igst = items.sum(:igst_amount).round(2)

    {
      taxable:  taxable.round(2),
      tax:      tax.round(2),
      cgst:     cgst,
      sgst:     sgst,
      igst:     igst,
      invoices: confirmed_sales.count
    }
  end

  def input_tax_summary
    items = PurchaseInvoiceItem
              .joins(:purchase_invoice)
              .where(purchase_invoices: { organisation_id: @organisation.id, status: 'confirmed' })
              .where(purchase_invoices: { invoice_date: @period_start..@period_end })

    taxable = items.sum(:taxable_amount)
    tax     = items.sum(:tax_amount)

    # Read directly from proper columns (set by confirm! via state comparison).
    # supply_type = 'intra_state' → cgst_amount + sgst_amount
    # supply_type = 'inter_state' → igst_amount
    cgst = items.sum(:cgst_amount).round(2)
    sgst = items.sum(:sgst_amount).round(2)
    igst = items.sum(:igst_amount).round(2)

    {
      taxable:  taxable.round(2),
      tax:      tax.round(2),
      cgst:     cgst,
      sgst:     sgst,
      igst:     igst,
      invoices: confirmed_purchases.count
    }
  end

  def net_gst_payable(output, input)
    {
      cgst: (output[:cgst] - input[:cgst]).round(2),
      sgst: (output[:sgst] - input[:sgst]).round(2),
      igst: (output[:igst] - input[:igst]).round(2),
      total: (output[:tax] - input[:tax]).round(2)
    }
  end

  def gstr1_hsn_summary
    sql = <<~SQL
      SELECT
        ph.hsn_code,
        sales_invoice_items.gst_rate,
        COUNT(DISTINCT sales_invoice_items.sales_invoice_id) AS invoice_count,
        SUM(sales_invoice_items.quantity)                    AS total_qty,
        SUM(sales_invoice_items.taxable_amount)              AS total_taxable,
        SUM(sales_invoice_items.tax_amount)                  AS total_tax
      FROM sales_invoice_items
      JOIN sales_invoices ON sales_invoices.id = sales_invoice_items.sales_invoice_id
      JOIN products ph    ON ph.id = sales_invoice_items.product_id
      WHERE sales_invoices.organisation_id = #{@organisation.id}
        AND sales_invoices.status = 'confirmed'
        AND sales_invoices.invoice_date BETWEEN '#{@period_start}' AND '#{@period_end}'
      GROUP BY ph.hsn_code, sales_invoice_items.gst_rate
      ORDER BY ph.hsn_code
    SQL
    ActiveRecord::Base.connection.exec_query(sql).to_a
  end

  def gstr1_due_date
    # GSTR-1 due: 11th of month following the tax period
    (Date.new(@period_year, @period_month, 1) + 1.month).change(day: 11)
  end

  def gstr3b_due_date
    # GSTR-3B due: 20th of month following the tax period
    (Date.new(@period_year, @period_month, 1) + 1.month).change(day: 20)
  end
  # ── Shared ITC set-off calculator ────────────────────────────────────────
  # Used by both gstr3b (display) and close_period (persist).
  # Returns a hash with payable, credit, and utilisation per tax head.
  def run_itc_setoff(output:, input:, opening:)
    total_igst_itc = (opening[:igst] + input[:igst]).round(2)
    total_cgst_itc = (opening[:cgst] + input[:cgst]).round(2)
    total_sgst_itc = (opening[:sgst] + input[:sgst]).round(2)

    igst_itc = total_igst_itc
    igst_out = output[:igst].to_f
    s1 = [igst_itc, igst_out].min; igst_out -= s1; igst_itc -= s1

    cgst_out = output[:cgst].to_f
    s2 = [igst_itc, cgst_out].min; cgst_out -= s2; igst_itc -= s2

    sgst_out = output[:sgst].to_f
    s3 = [igst_itc, sgst_out].min; sgst_out -= s3; igst_itc -= s3

    cgst_itc = total_cgst_itc
    s4 = [cgst_itc, cgst_out].min; cgst_out -= s4; cgst_itc -= s4
    s5 = [cgst_itc, igst_out].min; igst_out -= s5; cgst_itc -= s5

    sgst_itc = total_sgst_itc
    s6 = [sgst_itc, sgst_out].min; sgst_out -= s6; sgst_itc -= s6
    s7 = [sgst_itc, igst_out].min; igst_out -= s7; sgst_itc -= s7

    {
      igst_payable:  igst_out.round(2),
      cgst_payable:  cgst_out.round(2),
      sgst_payable:  sgst_out.round(2),
      igst_credit:   igst_itc.round(2),
      cgst_credit:   cgst_itc.round(2),
      sgst_credit:   sgst_itc.round(2),
      utilisation: {
        igst_vs_igst: s1.round(2), igst_vs_cgst: s2.round(2),
        igst_vs_sgst: s3.round(2), cgst_vs_cgst: s4.round(2),
        cgst_vs_igst: s5.round(2), sgst_vs_sgst: s6.round(2),
        sgst_vs_igst: s7.round(2)
      }
    }
  end

  # Period-scoped summary helpers used by close_period
  # (gstr3b uses @period_start/@period_end set by set_period before_action)
  def output_tax_summary_for(year:, month:)
    start_date = Date.new(year, month, 1)
    end_date   = start_date.end_of_month
    items = SalesInvoiceItem
              .joins(:sales_invoice)
              .where(sales_invoices: { organisation_id: @organisation.id, status: 'confirmed' })
              .where(sales_invoices: { invoice_date: start_date..end_date })
    {
      taxable: items.sum(:taxable_amount).round(2),
      tax:     items.sum(:tax_amount).round(2),
      cgst:    items.sum(:cgst_amount).round(2),
      sgst:    items.sum(:sgst_amount).round(2),
      igst:    items.sum(:igst_amount).round(2)
    }
  end

  def input_tax_summary_for(year:, month:)
    start_date = Date.new(year, month, 1)
    end_date   = start_date.end_of_month
    items = PurchaseInvoiceItem
              .joins(:purchase_invoice)
              .where(purchase_invoices: { organisation_id: @organisation.id, status: 'confirmed' })
              .where(purchase_invoices: { invoice_date: start_date..end_date })
    {
      taxable: items.sum(:taxable_amount).round(2),
      tax:     items.sum(:tax_amount).round(2),
      cgst:    items.sum(:cgst_amount).round(2),
      sgst:    items.sum(:sgst_amount).round(2),
      igst:    items.sum(:igst_amount).round(2)
    }
  end

end