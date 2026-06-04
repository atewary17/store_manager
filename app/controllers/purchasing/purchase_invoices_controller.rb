# app/controllers/purchasing/purchase_invoices_controller.rb
class Purchasing::PurchaseInvoicesController < Purchasing::BaseController

  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :confirm, :update_due_date]

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
      invoice_date:  Date.today,
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

    # Stamp supplier_hint from the form-level selector into each item's metadata.
    # The item metadata field carries it through resolve_product for supplier-aware matching.
    # Items built from the form already have metadata[supplier_hint] set via the hidden field,
    # but we enforce it here to ensure nothing is missed.
    supplier_hint = params[:supplier_hint].to_s.strip.presence
    if supplier_hint
      @invoice.purchase_invoice_items.each do |item|
        item.metadata = item.metadata.merge('supplier_hint' => supplier_hint)
      end
    end

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
    # Do NOT build blank rows on edit — existing items are already loaded.
    # User clicks "+ Add Row" button to add more items.
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
      begin
        ActivityLogger.log(
          organisation:     @invoice.organisation,
          user:             current_user,
          activity_type:    'purchase',
          activity_subtype: 'confirmed',
          description:      "Purchase invoice #{@invoice.invoice_number} confirmed",
          reference:        @invoice,
          metadata:         { invoice_number: @invoice.invoice_number, supplier: @invoice.supplier&.name }.compact
        )
      rescue => e
        Rails.logger.warn("[ActivityLog] purchase confirm #{@invoice.id}: #{e.message}")
      end
      redirect_to purchasing_purchase_invoice_path(@invoice),
        notice: "Invoice confirmed. Stock updated for #{@invoice.purchase_invoice_items.matched.count} product(s)."
    else
      redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: "Could not confirm: #{@invoice.errors.full_messages.join(', ')}"
    end
  end

  # PATCH /purchasing/purchase_invoices/:id/update_due_date
  def update_due_date
    if @invoice.fully_paid?
      return redirect_to purchasing_purchase_invoice_path(@invoice),
        alert: 'Invoice is fully paid — due date cannot be changed.'
    end

    new_date = params.dig(:purchase_invoice, :payment_due_date).presence
    @invoice.update_column(:payment_due_date, new_date)
    redirect_to purchasing_purchase_invoice_path(@invoice),
      notice: new_date ? 'Due date updated.' : 'Due date cleared.'
  end

  # TODO Step 7 — sales filter will be tightened to catalogue_status: approved
  # GET /purchasing/purchase_invoices/product_search
  def product_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    q_like        = "%#{q.downcase}%"
    supplier_hint = params[:supplier_hint].to_s.strip

    # Scope to the supplier's brand when a hint is provided — keeps autocomplete relevant.
    brand_filter = case supplier_hint
                   when 'asian_paints'
                     Brand.where('LOWER(name) = ?', 'asian paints').first
                   when 'shalimar_paints'
                     Brand.where('LOWER(name) LIKE ?', '%shalimar%').first
                   end

    active_base = Product.for_org(@organisation).where(active: true).includes(:brand, :base_uom)
    active_base = active_base.where(brand: brand_filter) if brand_filter

    active_products = active_base.where(
      'LOWER(products.description) LIKE :q
       OR LOWER(products.material_code) LIKE :q
       OR LOWER(products.product_code)  LIKE :q
       OR LOWER(products.pack_code)     LIKE :q',
      q: q_like
    ).limit(10)

    # AI-enriched pending products (same brand scope if applicable)
    pending_base = Product
      .joins(:organisation_products)
      .where(organisation_products: { organisation_id: @organisation.id })
      .where(active: false)
      .where("products.metadata->>'source' = 'ai_enrichment'")
      .includes(:brand, :base_uom)
    pending_base = pending_base.where(brand: brand_filter) if brand_filter

    pending_products = pending_base.where(
      'LOWER(products.description) LIKE :q OR LOWER(products.material_code) LIKE :q',
      q: q_like
    ).limit(5)

    results = active_products.map  { |p| format_product(p, 'matched') } +
              pending_products.map { |p| format_product(p, 'pending') }

    render json: results
  end

  private

  def format_product(p, status)
    half_gst = (p.gst_rate.to_f / 2).round(2)
    label    = [p.brand&.name, p.pack_code, p.description].compact_blank.join(' — ')
    label    = "[PENDING] #{label}" if status == 'pending'
    {
      id:            p.id,
      label:         label,
      description:   p.description,
      material_code: p.material_code,
      pack_code:     p.pack_code,
      uom:           p.base_uom&.short_name,
      gst_rate:      p.gst_rate.to_f,
      cgst:          half_gst,
      sgst:          half_gst,
      status:        status  # 'matched' | 'pending'
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
      :delivery_date, :payment_due_date, :status,
      metadata: {},
      purchase_invoice_items_attributes: [
        :id, :product_id, :quantity, :unit_rate, :total_amount,
        :gst_rate, :taxable_amount, :tax_amount,
        :discount_percent, :discount_amount,
        :unmatched, :_destroy,
        metadata: {}
      ]
    )
  end

end