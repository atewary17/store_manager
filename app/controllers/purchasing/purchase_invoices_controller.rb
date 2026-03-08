# app/controllers/purchasing/purchase_invoices_controller.rb
class Purchasing::PurchaseInvoicesController < Purchasing::BaseController

  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :confirm]

  # GET /purchasing/purchase_invoices
  def index
    @invoices = PurchaseInvoice
      .for_org(@organisation.id)
      .includes(:supplier, :user, :purchase_invoice_items)
      .recent

    @invoices = @invoices.where(status: params[:status]) if params[:status].present?

    @draft_count     = PurchaseInvoice.for_org(@organisation.id).draft.count
    @confirmed_count = PurchaseInvoice.for_org(@organisation.id).confirmed.count
  end

  # GET /purchasing/purchase_invoices/:id
  def show
  end

  # GET /purchasing/purchase_invoices/new
  def new
    @invoice = PurchaseInvoice.new(
      organisation: @organisation,
      delivery_date: Date.today,
      status: 'draft'
    )
    # Start with 3 blank item rows
    3.times { @invoice.purchase_invoice_items.build }
    load_form_data
  end

  # POST /purchasing/purchase_invoices
  def create
    @invoice = PurchaseInvoice.new(invoice_params)
    @invoice.organisation = @organisation
    @invoice.user         = current_user

    if @invoice.save
      redirect_to purchasing_purchase_invoice_path(@invoice),
        notice: 'Invoice saved as draft.'
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end

  # GET /purchasing/purchase_invoices/:id/edit
  def edit
    redirect_to purchasing_purchase_invoice_path(@invoice),
      alert: 'Confirmed invoices cannot be edited.' if @invoice.confirmed?
    # Ensure at least 3 empty rows for adding more items
    3.times { @invoice.purchase_invoice_items.build }
    load_form_data
  end

  # PATCH /purchasing/purchase_invoices/:id
  def update
    if @invoice.confirmed?
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: 'Confirmed invoices cannot be edited.' and return
    end

    if @invoice.update(invoice_params)
      redirect_to purchasing_purchase_invoice_path(@invoice),
        notice: 'Invoice updated.'
    else
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /purchasing/purchase_invoices/:id
  def destroy
    if @invoice.confirmed?
      redirect_to purchasing_purchase_invoices_path,
        alert: 'Confirmed invoices cannot be deleted.' and return
    end
    @invoice.destroy
    redirect_to purchasing_purchase_invoices_path, notice: 'Draft invoice deleted.'
  end

  # POST /purchasing/purchase_invoices/:id/confirm
  def confirm
    if @invoice.confirmed?
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: 'Already confirmed.' and return
    end

    if @invoice.purchase_invoice_items.empty?
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: 'Cannot confirm — no items added.' and return
    end

    if @invoice.confirm!(current_user)
      redirect_to purchasing_purchase_invoice_path(@invoice),
        notice: "Invoice confirmed. Stock updated for #{@invoice.purchase_invoice_items.matched.count} product(s)."
    else
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: "Could not confirm: #{@invoice.errors.full_messages.join(', ')}"
    end
  end

  # GET /purchasing/purchase_invoices/product_search
  def product_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    products = Product.active
      .includes(:brand, :base_uom)
      .where(
        'LOWER(products.description) LIKE :q
         OR LOWER(products.material_code) LIKE :q
         OR LOWER(products.product_code)  LIKE :q
         OR LOWER(products.pack_code)     LIKE :q',
        q: "%#{q.downcase}%"
      )
      .limit(10)

    render json: products.map { |p|
      half_gst = (p.gst_rate.to_f / 2).round(2)
      {
        id:            p.id,
        label:         [p.brand&.name, p.pack_code, p.description].compact_blank.join(' — '),
        description:   p.description,
        material_code: p.material_code,
        pack_code:     p.pack_code,
        uom:           p.base_uom&.short_name,
        gst_rate:      p.gst_rate.to_f,
        cgst:          half_gst,
        sgst:          half_gst
      }
    }
  end

  private

  def set_invoice
    @invoice = PurchaseInvoice.includes(:purchase_invoice_items)
                              .find(params[:id])
  end

  def load_form_data
    @suppliers = Supplier.active.ordered
  end

  def invoice_params
    params.require(:purchase_invoice).permit(
      :supplier_id, :invoice_number, :invoice_date,
      :delivery_date, :status,
      metadata: {},
      purchase_invoice_items_attributes: [
        :id, :product_id, :quantity, :unit_rate, :total_amount,
        :unmatched, :_destroy,
        metadata: {}
      ]
    )
  end

end