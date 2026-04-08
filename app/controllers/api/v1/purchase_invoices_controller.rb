# app/controllers/api/v1/purchase_invoices_controller.rb
#
# Mobile API for purchase invoices.
# Uses IDENTICAL model logic as the web controller — same confirm!, same GST calc,
# same stock updates. Only the input/output format changes (JSON instead of HTML form).

class Api::V1::PurchaseInvoicesController < Api::V1::BaseController

  before_action :set_invoice, only: [:show, :confirm]

  # GET /api/v1/purchase_invoices
  # Optional filters: ?status=draft|confirmed&page=1&per_page=20
  def index
    invoices = PurchaseInvoice
      .for_org(@organisation.id)
      .includes(:supplier, :purchase_invoice_items)
      .recent

    invoices = invoices.where(status: params[:status]) if params[:status].present?

    # Simple pagination without kaminari — offset/limit
    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
    page     = (params[:page]     || 1).to_i.clamp(1, 10_000)
    total    = invoices.count
    invoices = invoices.offset((page - 1) * per_page).limit(per_page)

    render_success(
      invoices: invoices.map { |inv| invoice_summary(inv) },
      meta: {
        total:    total,
        page:     page,
        per_page: per_page,
        pages:    (total.to_f / per_page).ceil
      }
    )
  end

  # GET /api/v1/purchase_invoices/:id
  def show
    render_success(invoice: invoice_detail(@invoice))
  end

  # POST /api/v1/purchase_invoices
  # Creates a draft invoice. Items are nested inside the payload.
  # The mobile app can either create-then-confirm in one flow, or create draft
  # and confirm separately (useful if user needs to review before confirming).
  def create
    @invoice = PurchaseInvoice.new(invoice_params)
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

  # POST /api/v1/purchase_invoices/:id/confirm
  # Confirms the invoice: calculates GST, updates stock, sets status = confirmed.
  # Mirrors EXACTLY what the web confirm action does — same model method.
  def confirm
    if @invoice.confirmed?
      return render_error(:unprocessable_entity, 'Invoice is already confirmed')
    end

    if @invoice.purchase_invoice_items.empty?
      return render_error(:unprocessable_entity, 'Cannot confirm — no items added')
    end

    # confirm! returns true on success, false on failure (not a hash)
    result = @invoice.confirm!(current_user)

    unless result
      return render_error(:unprocessable_entity,
        @invoice.errors.full_messages.any? ?
          @invoice.errors.full_messages.join(', ') :
          'Could not confirm invoice')
    end

    @invoice.reload
    render_success(
      invoice: invoice_detail(@invoice),
      message: "Invoice #{@invoice.display_number} confirmed. " \
               "Stock updated for #{@invoice.purchase_invoice_items.count} item(s)."
    )
  end

  # POST /api/v1/purchase_invoices/from_digitiser
  # Accepts the raw JSON structure produced by the digitiser / mobile scanner.
  # Maps it directly to a purchase invoice without requiring field renaming.
  #
  # Expected body shape (same as your digitiser output):
  # {
  #   "header":   { "invoice_number": "...", "invoice_date": "...", ... },
  #   "supplier": { "gstin": "...", "name": "..." },
  #   "items":    [ { "description": "...", "quantity": "6.0", "total_amount": "1654.53", ... } ]
  # }
  def from_digitiser
    header   = params[:header]   || {}
    supplier_data = params[:supplier] || {}
    items_data    = params[:items]    || []

    # ── Resolve supplier by GSTIN, fall back to name search ──────────
    supplier = nil
    if supplier_data[:gstin].present?
      supplier = Supplier.where(organisation: @organisation)
                         .find_by(gstin: supplier_data[:gstin])
    end
    if supplier.nil? && supplier_data[:name].present?
      # Case-insensitive partial match
      supplier = Supplier.where(organisation: @organisation)
                         .where('LOWER(name) LIKE ?', "%#{supplier_data[:name].downcase.strip}%")
                         .first
    end

    if supplier.nil?
      return render_error(:unprocessable_entity,
        "Supplier not found. GSTIN: #{supplier_data[:gstin]}, Name: #{supplier_data[:name]}. "         "Create the supplier in the app first, or pass supplier_id directly.",
        code: 'SUPPLIER_NOT_FOUND')
    end

    # ── Build nested items attributes ─────────────────────────────────
    items_attrs = items_data.map do |item|
      # Resolve product by material_code, then by description
      product = nil
      if item[:material_code].present?
        product = Product.for_org(@organisation)
                         .find_by(material_code: item[:material_code])
      end
      if product.nil? && item[:description].present?
        product = Product.for_org(@organisation)
                         .where('LOWER(description) LIKE ?',
                                "%#{item[:description].to_s.downcase.strip}%")
                         .first
      end

      {
        product_id:       product&.id,
        quantity:         item[:quantity].to_f,
        unit_rate:        0,  # recalculated by confirm!
        total_amount:     item[:total_amount].to_f,
        discount_percent: item[:discount_percent].to_f,
        discount_amount:  item[:discount_amount].to_f,
        gst_rate:         0,
        taxable_amount:   0,
        tax_amount:       0,
        supply_type:      'intra_state',
        cgst_amount:      0,
        sgst_amount:      0,
        igst_amount:      0,
        unmatched:        product.nil?,
        metadata: {
          'description'      => item[:description],
          'hsn_code'         => item[:hsn_code],
          'material_code'    => item[:material_code],
          'cgst_percent'     => item[:cgst_percent].to_f,
          'sgst_percent'     => item[:sgst_percent].to_f,
          'igst_percent'     => item[:igst_percent].to_f,
          'pack_size'        => item[:pack_size],
          'raw_description'  => item[:description],
          'discount_percent' => item[:discount_percent].to_s
        }
      }
    end

    # ── Build and save the invoice ────────────────────────────────────
    @invoice = PurchaseInvoice.new(
      organisation:  @organisation,
      user:          current_user,
      supplier:      supplier,
      invoice_number: header[:invoice_number],
      invoice_date:   header[:invoice_date],
      delivery_date:  header[:delivery_date].presence || header[:invoice_date],
      status:         'draft',
      total_amount:        0,
      total_taxable_amount: 0,
      total_tax_amount:     0,
      metadata: {
        'irn'                  => header[:irn],
        'place_of_supply'      => header[:place_of_supply],
        'delivery_number'      => header[:delivery_number],
        'cash_discount_amount' => header[:cash_discount_amount],
        'cash_discount_percent'=> header[:cash_discount_percent],
        'eway_bill'            => header[:eway_bill],
        'lr_number'            => header[:lr_number],
        'vehicle_number'       => header[:vehicle_number],
        'po_reference'         => header[:po_reference]
      }
    )

    items_attrs.each do |attrs|
      @invoice.purchase_invoice_items.build(attrs)
    end

    ActiveRecord::Base.transaction do
      if @invoice.save
        unmatched_count = @invoice.purchase_invoice_items.count(&:unmatched?)
        render_success(
          {
            invoice:          invoice_detail(@invoice),
            unmatched_items:  unmatched_count,
            supplier_matched: supplier.name,
            message:          "Draft invoice created with #{items_data.size} items." \
                              "#{unmatched_count > 0 ? " #{unmatched_count} item(s) could not be matched to products — review in the web app before confirming." : ''}"
          },
          status: :created
        )
      else
        render_error(:unprocessable_entity,
          @invoice.errors.full_messages.join(', '))
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def set_invoice
    @invoice = PurchaseInvoice
      .for_org(@organisation.id)
      .find(params[:id])
  end

  # ── Strong params — mirrors web controller exactly ────────────────────
  def invoice_params
    params.require(:purchase_invoice).permit(
      :supplier_id, :invoice_number, :invoice_date,
      :delivery_date, :status,
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

  # ── Serialisers ───────────────────────────────────────────────────────

  def invoice_summary(inv)
    {
      id:              inv.id,
      invoice_number:  inv.display_number,
      invoice_date:    inv.invoice_date&.iso8601,
      delivery_date:   inv.delivery_date&.iso8601,
      status:          inv.status,
      supplier: {
        id:    inv.supplier&.id,
        name:  inv.supplier&.name,
        state: inv.supplier&.state
      },
      total_taxable:   inv.total_taxable_amount.to_f,
      total_tax:       inv.total_tax_amount.to_f,
      total_amount:    inv.total_amount.to_f,
      total_paid:      inv.total_paid.to_f,
      outstanding:     inv.outstanding_amount.to_f,
      items_count:     inv.purchase_invoice_items.size,
      created_at:      inv.created_at.iso8601
    }
  end

  def invoice_detail(inv)
    inv.reload if inv.respond_to?(:reload)
    {
      id:              inv.id,
      invoice_number:  inv.display_number,
      invoice_date:    inv.invoice_date&.iso8601,
      delivery_date:   inv.delivery_date&.iso8601,
      status:          inv.status,
      confirmed_at:    inv.confirmed_at&.iso8601,
      supplier: {
        id:         inv.supplier&.id,
        name:       inv.supplier&.name,
        gstin:      inv.supplier&.gstin,
        state:      inv.supplier&.state,
        state_code: inv.supplier&.state_code
      },
      totals: {
        taxable_amount:    inv.total_taxable_amount.to_f,
        tax_amount:        inv.total_tax_amount.to_f,
        total_amount:      inv.total_amount.to_f,
        total_paid:        inv.total_paid.to_f,
        outstanding:       inv.outstanding_amount.to_f
      },
      gst_summary: {
        # These columns are set on confirm — will be 0 while draft
        cgst: inv.purchase_invoice_items.sum(:cgst_amount).to_f,
        sgst: inv.purchase_invoice_items.sum(:sgst_amount).to_f,
        igst: inv.purchase_invoice_items.sum(:igst_amount).to_f
      },
      items: inv.purchase_invoice_items.map { |item|
        {
          id:               item.id,
          product_id:       item.product_id,
          product_name:     item.product&.description,
          hsn_code:         item.product&.hsn_code,
          quantity:         item.quantity.to_f,
          unit_rate:        item.unit_rate.to_f,
          gst_rate:         item.gst_rate.to_f,
          discount_percent: item.discount_percent.to_f,
          taxable_amount:   item.taxable_amount.to_f,
          tax_amount:       item.tax_amount.to_f,
          total_amount:     item.total_amount.to_f,
          supply_type:      item.supply_type,
          cgst_amount:      item.cgst_amount.to_f,
          sgst_amount:      item.sgst_amount.to_f,
          igst_amount:      item.igst_amount.to_f
        }
      },
      payments: inv.purchase_payments.map { |p|
        {
          id:             p.id,
          payment_number: p.payment_label,
          amount:         p.amount.to_f,
          payment_date:   p.payment_date&.iso8601,
          payment_mode:   p.payment_mode,
          notes:          p.notes
        }
      },
      created_at:  inv.created_at.iso8601,
      updated_at:  inv.updated_at.iso8601
    }
  end

end