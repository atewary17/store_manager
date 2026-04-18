# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @organisation = current_user.organisation
    return unless @organisation

    org_id      = @organisation.id
    month_start = Date.today.beginning_of_month
    today       = Date.today

    # ── Sales chart: daily totals for current month ────────────────────────
    raw_sales = SalesInvoice
      .for_org(org_id)
      .confirmed
      .where(invoice_date: month_start..today)
      .group(:invoice_date)
      .sum(:total_amount)

    @sales_chart_data = (month_start..today).map do |d|
      [d.day.to_s, (raw_sales[d] || 0).to_f.round(2)]
    end
    @sales_month_total = @sales_chart_data.sum { |_, v| v }

    # ── Purchase chart: daily totals for current month ─────────────────────
    raw_purchases = PurchaseInvoice
      .for_org(org_id)
      .confirmed
      .where(invoice_date: month_start..today)
      .group(:invoice_date)
      .sum(:total_amount)

    @purchase_chart_data = (month_start..today).map do |d|
      [d.day.to_s, (raw_purchases[d] || 0).to_f.round(2)]
    end
    @purchase_month_total = @purchase_chart_data.sum { |_, v| v }

    # ── Payables due: confirmed purchase invoices with outstanding balance ──
    @payables_due = PurchaseInvoice
      .for_org(org_id)
      .confirmed
      .includes(:supplier, :purchase_payments)
      .order(Arel.sql('payment_due_date ASC NULLS LAST'))
      .limit(30)
      .select { |inv| inv.outstanding_amount > 0 }
      .first(8)
  end
end
