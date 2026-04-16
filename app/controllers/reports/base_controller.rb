# app/controllers/reports/base_controller.rb
class Reports::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation
  before_action :set_date_range

  private

  def set_organisation
    if current_user.super_admin? && params[:organisation_id].present?
      @organisation = Organisation.find(params[:organisation_id])
    else
      @organisation = current_user.organisation
    end
    redirect_to dashboard_path, alert: 'No organisation found.' unless @organisation
  end

  # Default: current Indian financial year quarter
  # FY runs Apr 1 → Mar 31
  # Q1: Apr-Jun, Q2: Jul-Sep, Q3: Oct-Dec, Q4: Jan-Mar
  def set_date_range
    if params[:from].present? && params[:to].present?
      @date_from = Date.parse(params[:from]) rescue current_quarter[:from]
      @date_to   = Date.parse(params[:to])   rescue current_quarter[:to]
    else
      q          = current_quarter
      @date_from = q[:from]
      @date_to   = q[:to]
    end
    @period_label = "#{@date_from.strftime('%d %b %Y')} – #{@date_to.strftime('%d %b %Y')}"
  end

  def current_quarter
    today = Date.today
    # Determine financial year start
    fy_start = today.month >= 4 ? Date.new(today.year, 4, 1) : Date.new(today.year - 1, 4, 1)
    # Months from FY start
    months_elapsed = (today.year * 12 + today.month) - (fy_start.year * 12 + fy_start.month)
    q_idx = months_elapsed / 3  # 0=Q1, 1=Q2, 2=Q3, 3=Q4
    q_month_start = fy_start >> (q_idx * 3)
    q_month_end   = (q_month_start >> 3) - 1
    { from: q_month_start, to: q_month_end, label: "Q#{q_idx + 1}" }
  end

  def confirmed_sales
    SalesInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(invoice_date: @date_from..@date_to)
  end

  def confirmed_purchases
    PurchaseInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(invoice_date: @date_from..@date_to)
  end

  def confirmed_sales_items
    SalesInvoiceItem
      .joins(:sales_invoice)
      .where(
        sales_invoices: {
          organisation_id: @organisation.id,
          status:          'confirmed',
          invoice_date:    @date_from..@date_to
        }
      )
  end

  # Quarter labels for the filter quick-links
  def quarters_for_select
    today = Date.today
    fy_start = today.month >= 4 ? Date.new(today.year, 4, 1) : Date.new(today.year - 1, 4, 1)
    (0..3).map do |i|
      q_start = fy_start >> (i * 3)
      q_end   = (q_start >> 3) - 1
      label   = "Q#{i + 1} (#{q_start.strftime('%b')}–#{q_end.strftime('%b %Y')})"
      { label: label, from: q_start.iso8601, to: q_end.iso8601 }
    end
  end
  helper_method :quarters_for_select

end
