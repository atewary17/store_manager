# app/controllers/api/v1/sales_invoices_controller.rb
#
# Mobile API for sales invoices.
# compute_amounts on SalesInvoiceItem runs before_validation and automatically
# determines CGST/SGST vs IGST by comparing organisation.state vs customer.state.
# The mobile app does NOT need to send GST percents — it sends metadata with
# cgst_percent/sgst_percent from the product, and the model handles the rest.

class Api::V1::SalesInvoicesController < Api::V1::BaseController

  before_action :set_invoice, only: [:show, :confirm, :void]

  # GET /api/v1/sales_invoices
  def index
    invoices = SalesInvoice
      .for_org(@organisation.id)
      .includes(:customer, :sales_invoice_items)
      .recent

    invoices = invoices.where(status: params[:status]) if params[:status].present?

    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
    page     = (params[:page]     || 1).to_i.clamp(1, 10_000)
    total    = invoices.count
    invoices = invoices.offset((page - 1) * per_page).limit(per_page)

    render_success(
      invoices: invoices.map { |inv| invoice_summary(inv) },
      meta: { total: total, page: page, per_page: per_page,
              pages: (total.to_f / per_page).ceil }
    )
  end

  # GET /api/v1/sales_invoices/:id
  def show
    render_success(invoice: invoice_detail(@invoice))
  end

  # POST /api/v1/sales_invoices
  # Creates draft. The mobile app passes items with total_amount (GST-inclusive)
  # and metadata containing cgst_percent/sgst_percent from the product.
  # SalesInvoiceItem#compute_amounts does the back-calculation automatically.
  def create
    @invoice              = SalesInvoice.new(invoice_params)
    @invoice.organisation = @organisation
    @invoice.user         = current_user

    ActiveRecord::Base.transaction do
      if @invoice.save
        render_success({ invoice: invoice_detail(@invoice) }, status: :created)
      else
        render_error(:unprocessable_entity,
          @invoice.errors.full_messages.join(', '))
        raise ActiveRecord::Rollback
      end
    end
  end

  # POST /api/v1/sales_invoices/:id/confirm
  # Confirms invoice: deducts stock, calculates GST per-head, sets status = confirmed.
  def confirm
    return render_error(:unprocessable_entity, 'Already confirmed') if @invoice.confirmed?
    return render_error(:unprocessable_entity, 'No items on this invoice') if @invoice.sales_invoice_items.empty?

    result = @invoice.confirm!(current_user)

    if result[:success] == false
      return render_error(:unprocessable_entity,
        Array(result[:errors]).join(', '))
    end

    @invoice.reload
    render_success(
      invoice:     invoice_detail(@invoice),
      stock_lines: result[:stock_lines] || [],
      message:     "Invoice #{@invoice.display_number} confirmed."
    )
  end

  # POST /api/v1/sales_invoices/:id/void
  def void
    unless @invoice.confirmed?
      return render_error(:unprocessable_entity, 'Only confirmed invoices can be voided')
    end

    result = @invoice.void!(current_user)

    if result[:success]
      render_success(
        invoice:        invoice_detail(@invoice.reload),
        reversed_lines: result[:reversed_lines] || [],
        message:        'Invoice voided. Stock restored.'
      )
    else
      render_error(:unprocessable_entity, Array(result[:errors]).join(', '))
    end
  end

  private

  def set_invoice
    @invoice = SalesInvoice
      .for_org(@organisation.id)
      .find(params[:id])
  end

  # ── Strong params — mirrors web controller exactly ────────────────────
  def invoice_params
    params.require(:sales_invoice).permit(
      :customer_id, :invoice_number, :invoice_date, :payment_due_date,
      :payment_mode, :reverse_charge, :status,
      :overall_discount_amount,
      metadata: {},
      sales_invoice_items_attributes: [
        :id, :line_type, :product_id, :shade_catalogue_id,
        :base_product_id, :tinter_product_id,
        :description,
        :quantity, :unit_rate,
        :taxable_amount, :tax_amount, :total_amount,
        :_destroy,
        metadata: {}
      ]
    )
  end

  # ── Serialisers ───────────────────────────────────────────────────────

  def invoice_summary(inv)
    {
      id:             inv.id,
      invoice_number: inv.display_number,
      invoice_date:   inv.invoice_date&.iso8601,
      status:         inv.status,
      customer: {
        id:    inv.customer&.id,
        name:  inv.customer&.name || 'Walk-in',
        gstin: inv.customer&.gstin,
        state: inv.customer&.state
      },
      total_taxable:  inv.total_taxable_amount.to_f,
      total_tax:      inv.total_tax_amount.to_f,
      total_amount:   inv.total_amount.to_f,
      total_paid:     inv.total_paid.to_f,
      outstanding:    inv.outstanding_amount.to_f,
      payment_status: inv.payment_status,
      items_count:    inv.sales_invoice_items.size,
      created_at:     inv.created_at.iso8601
    }
  end

  def invoice_detail(inv)
    {
      id:               inv.id,
      invoice_number:   inv.display_number,
      invoice_date:     inv.invoice_date&.iso8601,
      payment_due_date: inv.payment_due_date&.iso8601,
      payment_mode:     inv.payment_mode,
      status:           inv.status,
      confirmed_at:     inv.confirmed_at&.iso8601,
      voided_at:        inv.voided_at&.iso8601,
      customer: {
        id:         inv.customer&.id,
        name:       inv.customer&.name || 'Walk-in',
        gstin:      inv.customer&.gstin,
        state:      inv.customer&.state,
        state_code: inv.customer&.state_code
      },
      totals: {
        taxable_amount:          inv.total_taxable_amount.to_f,
        tax_amount:              inv.total_tax_amount.to_f,
        overall_discount_amount: inv.overall_discount_amount.to_f,
        total_amount:            inv.total_amount.to_f,
        total_paid:              inv.total_paid.to_f,
        outstanding:             inv.outstanding_amount.to_f
      },
      gst_summary: {
        cgst: inv.sales_invoice_items.sum(:cgst_amount).to_f,
        sgst: inv.sales_invoice_items.sum(:sgst_amount).to_f,
        igst: inv.sales_invoice_items.sum(:igst_amount).to_f
      },
      items: inv.sales_invoice_items.map { |item|
        {
          id:            item.id,
          line_type:     item.line_type,
          product_id:    item.product_id,
          product_name:  item.product&.description || item.description,
          quantity:      item.quantity.to_f,
          unit_rate:     item.unit_rate.to_f,
          gst_rate:      item.gst_rate.to_f,
          taxable_amount: item.taxable_amount.to_f,
          tax_amount:    item.tax_amount.to_f,
          total_amount:  item.total_amount.to_f,
          supply_type:   item.supply_type,
          cgst_amount:   item.cgst_amount.to_f,
          sgst_amount:   item.sgst_amount.to_f,
          igst_amount:   item.igst_amount.to_f
        }
      },
      payments: inv.sale_payments.map { |p|
        {
          id:             p.id,
          receipt_number: p.receipt_label,
          amount:         p.amount.to_f,
          payment_date:   p.payment_date&.iso8601,
          payment_mode:   p.payment_mode
        }
      },
      created_at:  inv.created_at.iso8601,
      updated_at:  inv.updated_at.iso8601
    }
  end

end