# app/controllers/sales/sale_payments_controller.rb
class Sales::SalePaymentsController < Sales::BaseController

  before_action :set_invoice
  before_action :set_payment, only: [:show, :destroy]

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

  def payment_params
    params.require(:sale_payment).permit(
      :payment_date, :amount, :payment_mode, :reference_number, :notes
    )
  end

end
