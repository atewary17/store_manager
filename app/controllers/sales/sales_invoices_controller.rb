# app/controllers/sales/sales_invoices_controller.rb
class Sales::SalesInvoicesController < Sales::BaseController

  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :confirm, :preview, :void, :mark_as_paid]

  def index
    @invoices = SalesInvoice
      .for_org(@organisation.id)
      .includes(:customer, :user, :sales_invoice_items)
      .recent
    @invoices = @invoices.where(status: params[:status]) if params[:status].present?
    @draft_count     = SalesInvoice.for_org(@organisation.id).draft.count
    @confirmed_count = SalesInvoice.for_org(@organisation.id).confirmed.count
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        render pdf:         @invoice.display_number,
               layout:      'pdf',
               template:    'sales/sales_invoices/show_pdf',
               formats:     [:html],
               disposition: 'attachment',
               page_size:   'A4',
               encoding:    'UTF-8',
               dpi:          150,
               margin:      { top: '12mm', bottom: '12mm', left: '10mm', right: '10mm' }
      end
    end
  end

  # GET /sales/sales_invoices/:id/preview
  # Shown after save — review before confirming
  def preview; end

  def new
    @invoice = SalesInvoice.new(
      organisation: @organisation,
      invoice_date: Date.today,
      status:       'draft'
    )
    # No default rows — user adds via buttons
    load_form_data
  end

  def create
    @invoice              = SalesInvoice.new(invoice_params)
    @invoice.organisation = @organisation
    @invoice.user         = current_user

    if @invoice.save
      redirect_to preview_sales_sales_invoice_path(@invoice)
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to sales_sales_invoice_path(@invoice), alert: 'Confirmed invoices cannot be edited.' and return if @invoice.confirmed?
    load_form_data
  end

  def update
    redirect_to sales_sales_invoice_path(@invoice), alert: 'Confirmed invoices cannot be edited.' and return if @invoice.confirmed?
    if @invoice.update(invoice_params)
      redirect_to preview_sales_sales_invoice_path(@invoice)
    else
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    redirect_to sales_sales_invoices_path, alert: 'Confirmed invoices cannot be deleted.' and return if @invoice.confirmed?
    @invoice.destroy
    redirect_to sales_sales_invoices_path, notice: 'Draft invoice deleted.'
  end

  def confirm
    redirect_to sales_sales_invoice_path(@invoice), alert: 'Already confirmed.' and return if @invoice.confirmed?
    redirect_to sales_sales_invoice_path(@invoice), alert: 'No items on this invoice.' and return if @invoice.sales_invoice_items.empty?

    result = @invoice.confirm!(current_user)

    if result[:success]
      flash[:notice] = "Invoice confirmed."
      flash[:stock_lines] = result[:stock_lines]   # passed to show view
      redirect_to sales_sales_invoice_path(@invoice)
    else
      flash[:alert] = "Could not confirm: #{result[:errors]&.join(', ')}"
      redirect_to preview_sales_sales_invoice_path(@invoice)
    end
  end

  # POST /sales/sales_invoices/:id/mark_as_paid
  def mark_as_paid
    mode  = params[:payment_mode].presence || 'cash'
    notes = params[:notes].presence || 'Marked as fully paid'
    result = @invoice.mark_as_paid!(current_user, payment_mode: mode, notes: notes)
    if result[:success]
      redirect_to sales_sales_invoice_path(@invoice),
        notice: "Invoice marked as fully paid. Receipt: #{result[:payment].receipt_label}"
    else
      redirect_to sales_sales_invoice_path(@invoice),
        alert: result[:errors].join(', ')
    end
  end

  # POST /sales/sales_invoices/:id/void
  def void
    result = @invoice.void!(current_user)
    if result[:success]
      flash[:notice] = 'Invoice voided. Stock has been restored.'
      flash[:reversed_lines] = result[:reversed_lines]
      redirect_to sales_sales_invoice_path(@invoice)
    else
      redirect_to sales_sales_invoice_path(@invoice),
        alert: result[:errors].join(', ')
    end
  end

  # GET /sales/sales_invoices/product_search
  # Only products that exist in stock for this org (quantity > 0)
  def product_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    in_stock_ids = StockLevel
      .where(organisation_id: @organisation.id)
      .where('quantity > 0')
      .pluck(:product_id)

    products = Product.active
      .where(id: in_stock_ids)
      .includes(:brand, :base_uom, :product_category)
      .where('LOWER(products.description) LIKE :q OR LOWER(products.material_code) LIKE :q
              OR LOWER(products.pack_code) LIKE :q', q: "%#{q.downcase}%")
      .limit(10)

    render json: products.map { |p|
      half  = (p.gst_rate.to_f / 2).round(2)
      level = StockLevel.find_by(organisation_id: @organisation.id, product_id: p.id)
      {
        id:            p.id,
        label:         [p.brand&.name, p.pack_code, p.description].compact_blank.join(' — '),
        material_code: p.material_code,
        pack_code:     p.pack_code,
        uom:           p.base_uom&.short_name,
        mrp:           p.mrp,
        gst_rate:      p.gst_rate.to_f,
        cgst:          half,
        sgst:          half,
        stock_qty:     level&.quantity.to_f
      }
    }
  end

  # GET /sales/sales_invoices/base_search
  # Paint-category products in stock (for base selection on paint rows)
  def base_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    paint_cat_ids = ProductCategory.paint_types.pluck(:id)

    in_stock_ids = StockLevel
      .where(organisation_id: @organisation.id)
      .where('quantity > 0')
      .pluck(:product_id)

    products = Product.active
      .where(id: in_stock_ids)
      .where(product_category_id: paint_cat_ids)
      .includes(:brand, :base_uom)
      .where('LOWER(products.description) LIKE :q OR LOWER(products.material_code) LIKE :q
              OR LOWER(products.pack_code) LIKE :q', q: "%#{q.downcase}%")
      .limit(10)

    render json: products.map { |p|
      half  = (p.gst_rate.to_f / 2).round(2)
      level = StockLevel.find_by(organisation_id: @organisation.id, product_id: p.id)
      {
        id:        p.id,
        label:     [p.brand&.name, p.pack_code, p.description].compact_blank.join(' — '),
        uom:       p.base_uom&.short_name,
        mrp:       p.mrp,
        cgst:      half,
        sgst:      half,
        stock_qty: level&.quantity.to_f
      }
    }
  end

  # GET /sales/sales_invoices/shade_search
  def shade_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    shades = ShadeCatalogue.active
      .includes(:brand, :product_category)
      .where('LOWER(shade_catalogues.shade_code) LIKE :q OR LOWER(shade_catalogues.shade_name) LIKE :q
              OR LOWER(shade_catalogues.colour_family) LIKE :q', q: "%#{q.downcase}%")
      .limit(10)

    render json: shades.map { |s|
      { id: s.id, shade_code: s.shade_code, shade_name: s.shade_name,
        label: s.display_name, brand: s.brand&.name, colour_family: s.colour_family }
    }
  end

  private

  def set_invoice
    @invoice = SalesInvoice
      .includes(sales_invoice_items: [:product, :shade_catalogue, :base_product, :tinter_product])
      .find(params[:id])
  end

  def load_form_data
    @customers = Customer.for_org(@organisation.id).active.ordered
  end

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

end
