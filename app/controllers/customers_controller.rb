# app/controllers/customers_controller.rb
class CustomersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation
  before_action :set_customer, only: [:show, :edit, :update, :destroy]

  def index
    @customers = Customer.for_org(@organisation.id).ordered.includes(:sales_invoices)
    @total_count      = @customers.count
    @active_count     = @customers.where(active: true).count
    @total_invoiced   = SalesInvoice.confirmed.where(organisation: @organisation)
                                     .sum(:total_amount).to_f.round(2)
    @total_outstanding = SalesInvoice.confirmed.where(organisation: @organisation)
                          .joins(:sale_payments)
                          .select('sales_invoices.total_amount - COALESCE(SUM(sale_payments.amount),0) AS outstanding')
                          .group('sales_invoices.id')
                          .map { |i| i.outstanding.to_f }.sum.round(2)
  end

  def new
    @customer = Customer.new(organisation: @organisation)
  end

  def show
    @invoices = @customer.sales_invoices
                          .confirmed
                          .includes(:sale_payments)
                          .order(invoice_date: :desc)
                          .limit(20)

    @total_invoiced   = @customer.sales_invoices.confirmed.sum(:total_amount).to_f.round(2)
    @total_paid       = @customer.sales_invoices.confirmed
                                  .joins(:sale_payments)
                                  .sum('sale_payments.amount').to_f.round(2)
    @total_outstanding = (@total_invoiced - @total_paid).round(2)
    @invoice_count    = @customer.sales_invoices.confirmed.count
    @last_invoice     = @customer.sales_invoices.confirmed.maximum(:invoice_date)
    @draft_count      = @customer.sales_invoices.draft.count
  end

  def edit; end

  def create
    @customer = Customer.new(customer_params)
    @customer.organisation = @organisation
    respond_to do |format|
      if @customer.save
        format.html { redirect_to customers_path, notice: 'Customer created.' }
        format.json {
          render json: {
            id: @customer.id, name: @customer.name,
            phone: @customer.phone, gstin: @customer.gstin,
            state: @customer.state, state_code: @customer.state_code,
            address: @customer.address
          }
        }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @customer.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @customer.update(customer_params)
      redirect_to customers_path, notice: 'Customer updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @customer.can_delete?
      @customer.destroy
      redirect_to customers_path, notice: 'Customer deleted.'
    else
      redirect_to customers_path, alert: 'Cannot delete — customer has sales invoices.'
    end
  end

  def search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    customers = Customer.for_org(@organisation.id).active
      .where('LOWER(name) LIKE :q OR phone LIKE :q OR LOWER(gstin) LIKE :q',
             q: "%#{q.downcase}%")
      .order(:name).limit(8)

    render json: customers.map { |c|
      { id: c.id, name: c.name, phone: c.phone, gstin: c.gstin,
        state: c.state, state_code: c.state_code, address: c.address }
    }
  end

  private

  def set_organisation
    if current_user.super_admin? && params[:organisation_id].present?
      @organisation = Organisation.find(params[:organisation_id])
    else
      @organisation = current_user.organisation
    end
    redirect_to dashboard_path, alert: 'No organisation found.' unless @organisation
  end

  def set_customer
    @customer = Customer.for_org(@organisation.id).find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(
      :name, :phone, :gstin, :pan, :state, :state_code, :active,
      metadata: {}
    )
  end

end