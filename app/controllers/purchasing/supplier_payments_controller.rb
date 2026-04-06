# app/controllers/purchasing/supplier_payments_controller.rb
# Supplier Payments — record and view all payments made to suppliers.
class Purchasing::SupplierPaymentsController < Purchasing::BaseController

  before_action :set_invoice,  except: [:index, :payment_show]
  before_action :set_payment,  only:   [:destroy]
  before_action :set_payment_standalone, only: [:payment_show]

  # GET /purchasing/supplier_payments
  def index
    @payments = PurchasePayment
      .for_org(@organisation.id)
      .includes(:supplier, :user, purchase_invoice: :supplier)
      .recent

    @payments = @payments.for_supplier(params[:supplier_id]) if params[:supplier_id].present?
    @payments = @payments.where(payment_mode: params[:payment_mode]) if params[:payment_mode].present?
    @payments = @payments.where('payment_date >= ?', params[:from_date]) if params[:from_date].present?
    @payments = @payments.where('payment_date <= ?', params[:to_date])   if params[:to_date].present?

    if params[:q].present?
      term = "%#{params[:q].downcase}%"
      @payments = @payments.where(
        'LOWER(payment_number) LIKE :q OR LOWER(reference_number) LIKE :q', q: term
      )
    end

    @selected_supplier = Supplier.where(organisation: @organisation).find_by(id: params[:supplier_id])

    @total_paid      = @payments.sum(:amount)
    @payment_count   = @payments.count
    @supplier_count  = @payments.select(:supplier_id).distinct.count

    @per_page    = 50
    @page        = [params[:page].to_i, 1].max
    @total_pages = [(@payment_count.to_f / @per_page).ceil, 1].max
    @payments    = @payments.offset((@page - 1) * @per_page).limit(@per_page)

    @suppliers     = Supplier.where(organisation: @organisation).where(active: true).order(:name)
    @payment_modes = PurchasePayment::PAYMENT_MODES

    render 'purchasing/supplier_payments/index'
  end

  # GET /purchasing/supplier_payments/:id
  def payment_show
    @invoice  = @payment.purchase_invoice
    @supplier = @payment.supplier || @invoice&.supplier
    render 'purchasing/supplier_payments/payment_show'
  end

  # POST /purchasing/purchase_invoices/:purchase_invoice_id/supplier_payments
  def create
    @payment = @invoice.purchase_payments.build(payment_params)
    @payment.organisation = @organisation
    @payment.user         = current_user

    if @payment.save
      redirect_to purchasing_purchase_invoice_path(@invoice),
        notice: "Payment of ₹#{@payment.amount} recorded. Ref: #{@payment.payment_label}"
    else
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: @payment.errors.full_messages.join(', ')
    end
  end

  # DELETE /purchasing/purchase_invoices/:purchase_invoice_id/supplier_payments/:id
  def destroy
    @payment.destroy
    redirect_to purchasing_purchase_invoice_path(@invoice),
      notice: "Payment #{@payment.payment_label} deleted."
  end

  private

  def set_invoice
    @invoice = PurchaseInvoice
      .for_org(@organisation.id)
      .find(params[:purchase_invoice_id])
  end

  def set_payment
    @payment = @invoice.purchase_payments.find(params[:id])
  end

  def set_payment_standalone
    @payment = PurchasePayment.for_org(@organisation.id).find(params[:id])
  end

  def payment_params
    params.require(:purchase_payment).permit(
      :payment_date, :amount, :payment_mode, :reference_number, :notes
    )
  end

end
