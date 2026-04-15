# app/controllers/purchasing/suppliers_controller.rb
class Purchasing::SuppliersController < Purchasing::BaseController

  before_action :set_supplier, only: [:show, :edit, :update, :destroy]

  def index
    @suppliers = Supplier.for_org(@organisation.id).ordered.includes(:purchase_invoices)
    @total_count      = @suppliers.count
    @active_count     = @suppliers.where(active: true).count
    @total_invoiced   = PurchaseInvoice.confirmed.where(organisation: @organisation)
                                        .sum(:total_amount).to_f.round(2)
    @total_outstanding = PurchaseInvoice.confirmed.where(organisation: @organisation)
                          .joins(:purchase_payments)
                          .select('purchase_invoices.total_amount - COALESCE(SUM(purchase_payments.amount),0) AS outstanding')
                          .group('purchase_invoices.id')
                          .map { |i| i.outstanding.to_f }.sum.round(2)
  end

  def new
    @supplier = Supplier.new(organisation: @organisation)
  end

  def show
    @invoices = @supplier.purchase_invoices
                          .confirmed
                          .includes(:purchase_payments)
                          .order(invoice_date: :desc)
                          .limit(20)

    @total_invoiced   = @supplier.purchase_invoices.confirmed.sum(:total_amount).to_f.round(2)
    @total_paid       = @supplier.purchase_invoices.confirmed
                                  .joins(:purchase_payments)
                                  .sum('purchase_payments.amount').to_f.round(2)
    @total_outstanding = (@total_invoiced - @total_paid).round(2)
    @invoice_count    = @supplier.purchase_invoices.confirmed.count
    @last_invoice     = @supplier.purchase_invoices.confirmed.maximum(:invoice_date)
    @draft_count      = @supplier.purchase_invoices.draft.count
  end

  def edit; end

  def create
    @supplier = Supplier.new(supplier_params)
    @supplier.organisation = @organisation
    respond_to do |format|
      if @supplier.save
        format.html { redirect_to purchasing_suppliers_path, notice: 'Supplier created.' }
        format.json {
          render json: {
            id: @supplier.id, name: @supplier.name,
            gstin: @supplier.gstin, pan: @supplier.pan,
            state: @supplier.state, state_code: @supplier.state_code,
            address: @supplier.address
          }
        }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @supplier.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to purchasing_suppliers_path, notice: 'Supplier updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @supplier.can_delete?
      @supplier.destroy
      redirect_to purchasing_suppliers_path, notice: 'Supplier deleted.'
    else
      redirect_to purchasing_suppliers_path,
        alert: 'Cannot delete — supplier has purchase invoices.'
    end
  end

  # GET /purchasing/suppliers/search
  def search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    suppliers = Supplier.for_org(@organisation.id).active
      .where('LOWER(name) LIKE :q OR LOWER(gstin) LIKE :q', q: "%#{q.downcase}%")
      .order(:name)
      .limit(8)

    render json: suppliers.map { |s|
      {
        id:          s.id,
        name:        s.name,
        gstin:       s.gstin,
        pan:         s.pan,
        state:       s.state,
        state_code:  s.state_code,
        address:     s.address
      }
    }
  end

  private

  def set_supplier
    @supplier = Supplier.for_org(@organisation.id).find(params[:id])
  end

  def supplier_params
    params.require(:supplier).permit(
      :name, :gstin, :pan, :state, :state_code, :active,
      metadata: [:address, {}]
    )
  end

end