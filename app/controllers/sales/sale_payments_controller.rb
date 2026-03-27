# app/controllers/sales/sale_payments_controller.rb
class Sales::SalePaymentsController < Sales::BaseController

  before_action :set_invoice,  except: [:index, :payment_show]
  before_action :set_payment,  only:   [:show, :destroy]
  before_action :set_payment_standalone, only: [:payment_show]

  # GET /sales/customer_receipts
  # All receipts/payments across all customers for this org — most recent first
  def index
    @payments = SalePayment
      .for_org(@organisation.id)
      .includes(:customer, :user, sales_invoice: :customer)
      .recent

    # ── Filters ──
    if params[:customer_id].present?
      @payments = @payments.for_customer(params[:customer_id])
      @selected_customer = Customer.for_org(@organisation.id).find_by(id: params[:customer_id])
    end

    if params[:payment_mode].present?
      @payments = @payments.where(payment_mode: params[:payment_mode])
    end

    if params[:from_date].present?
      @payments = @payments.where('payment_date >= ?', params[:from_date])
    end

    if params[:to_date].present?
      @payments = @payments.where('payment_date <= ?', params[:to_date])
    end

    if params[:q].present?
      term = "%#{params[:q].downcase}%"
      @payments = @payments.where(
        'LOWER(receipt_number) LIKE :q OR LOWER(reference_number) LIKE :q', q: term
      )
    end

    # Stats (before pagination — on full filtered set)
    @total_received    = @payments.sum(:amount)
    @payment_count     = @payments.count
    @customer_count    = @payments.select(:customer_id).distinct.count

    # Pagination
    @per_page   = 50
    @page       = [params[:page].to_i, 1].max
    @total_pages = [(@payment_count.to_f / @per_page).ceil, 1].max
    @payments   = @payments.offset((@page - 1) * @per_page).limit(@per_page)

    @customers     = Customer.for_org(@organisation.id).active.ordered
    @payment_modes = SalePayment::PAYMENT_MODES

    render 'sales/customer_receipts/index'
  end

  # GET /sales/customer_receipts/:id
  # Standalone receipt detail (without needing the invoice in the URL)
  def payment_show
    @invoice  = @payment.sales_invoice
    @customer = @payment.customer || @invoice&.customer

    render 'sales/customer_receipts/payment_show'
  end

  # POST /sales/sales_invoices/:sales_invoice_id/sale_payments
  def create
    @payment = @invoice.sale_payments.build(payment_params)
    @payment.organisation = @organisation
    @payment.user         = current_user

    if @payment.save
      redirect_to sales_sales_invoice_path(@invoice),
        notice: "Payment of ₹#{@payment.amount} recorded. Receipt: #{@payment.receipt_label}"
    else
      redirect_to sales_sales_invoice_path(@invoice),
        alert: @payment.errors.full_messages.join(', ')
    end
  end

  # GET /sales/sales_invoices/:sales_invoice_id/sale_payments/:id
  # Receipt PDF
  def show
    respond_to do |format|
      format.html { redirect_to sales_sales_invoice_path(@invoice) }
      format.pdf do
        render pdf:         @payment.receipt_label,
               layout:      'pdf',
               template:    'sales/sale_payments/receipt',
               formats:     [:html],
               disposition: 'attachment',
               page_size:   'A4',
               encoding:    'UTF-8'
      end
    end
  end

  # DELETE /sales/sales_invoices/:sales_invoice_id/sale_payments/:id
  def destroy
    @payment.destroy
    redirect_to sales_sales_invoice_path(@invoice),
      notice: "Payment #{@payment.receipt_label} deleted."
  end

  private

  def set_invoice
    @invoice = SalesInvoice
      .for_org(@organisation.id)
      .find(params[:sales_invoice_id])
  end

  def set_payment
    @payment = @invoice.sale_payments.find(params[:id])
  end

  def set_payment_standalone
    @payment = SalePayment.for_org(@organisation.id).find(params[:id])
  end

  def payment_params
    params.require(:sale_payment).permit(
      :payment_date, :amount, :payment_mode, :reference_number, :notes
    )
  end

end