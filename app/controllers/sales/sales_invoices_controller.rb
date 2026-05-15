# app/controllers/sales/sales_invoices_controller.rb
class Sales::SalesInvoicesController < Sales::BaseController

  before_action :set_invoice, only: [:show, :edit, :update, :destroy, :confirm, :preview, :void, :mark_as_paid, :update_due_date]

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
      # Log AFTER transaction commits — invoice is more important than the log
      log_sales_activity  # each item rescues internally; never raises

      if tinting_prompt_needed?
        flash[:tinting_prompt]   = true
        flash[:tinting_brand_id] = tinting_brand_id_for_invoice
        flash[:tinting_action]   = @invoice.organisation.settings['tinting_prompt_action'].presence || 'new_tab'
      end
      flash[:notice]      = "Invoice confirmed."
      flash[:stock_lines] = result[:stock_lines]
      redirect_to sales_sales_invoice_path(@invoice)
    else
      flash[:alert] = "Could not confirm: #{result[:errors]&.join(', ')}"
      redirect_to preview_sales_sales_invoice_path(@invoice)
    end
  end

  # POST /sales/sales_invoices/tinting_snooze
  def tinting_snooze
    org = @organisation
    current_total = org.tinting_litres_since_reset.values.sum
    threshold     = org.settings['tinting_prompt_threshold_litres'].to_f
    threshold     = 20.0 if threshold <= 0

    snooze_until  = case params[:snooze_type]
                    when 'skip' then current_total + (threshold / 2.0)
                    else             current_total + threshold
                    end

    session[:tinting_snooze_until_litres] = snooze_until
    render json: { ok: true }
  end

  # PATCH /sales/sales_invoices/:id/update_due_date
  # Allows updating payment_due_date on any non-voided invoice that is not fully paid.
  def update_due_date
    if @invoice.voided?
      return redirect_to sales_sales_invoice_path(@invoice), alert: 'Cannot update a voided invoice.'
    end
    if @invoice.fully_paid?
      return redirect_to sales_sales_invoice_path(@invoice), alert: 'Invoice is fully paid — due date cannot be changed.'
    end

    new_date = params.dig(:sales_invoice, :payment_due_date).presence
    @invoice.update_column(:payment_due_date, new_date)
    redirect_to sales_sales_invoice_path(@invoice), notice: new_date ? 'Due date updated.' : 'Due date cleared.'
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

    products = Product.for_org(@organisation)
      .active
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
  # Paint base products in stock — excludes primers, putties, sealers, thinners.
  # Filter: is_tinting_base=true (synced products) OR paint category + no non-base keywords.
  def base_search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    paint_cat_ids = ProductCategory.paint_types.pluck(:id)

    in_stock_ids = StockLevel
      .where(organisation_id: @organisation.id)
      .where('quantity > 0')
      .pluck(:product_id)

    non_base_exclusion = %w[primer putty sealer thinner bond filler]
      .map { |kw| "LOWER(products.description) NOT LIKE '%#{kw}%'" }
      .join(' AND ')

    base_filter = "products.metadata->>'is_tinting_base' = 'true'
                   OR (#{non_base_exclusion})"

    # Build a LEFT JOIN on brands so brand name is searchable without N+1
    tokens = q.downcase.split.select { |t| t.length >= 2 }
    tokens = [q.downcase] if tokens.empty?

    products = Product.for_org(@organisation)
      .active
      .where(id: in_stock_ids)
      .where(product_category_id: paint_cat_ids)
      .where(base_filter)
      .joins('LEFT JOIN brands ON brands.id = products.brand_id')
      .includes(:base_uom)
      .then { |scope|
        tokens.reduce(scope) { |s, token|
          term = "%#{token}%"
          s.where(
            "LOWER(brands.name)                            LIKE :t OR
             LOWER(products.description)                   LIKE :t OR
             LOWER(products.material_code)                 LIKE :t OR
             LOWER(products.pack_code)                     LIKE :t OR
             LOWER(COALESCE(products.shade_code, ''))      LIKE :t OR
             LOWER(COALESCE(products.metadata->>'product_line_desc', '')) LIKE :t OR
             LOWER(COALESCE(products.metadata->>'pack_size_desc',    '')) LIKE :t OR
             LOWER(COALESCE(products.metadata->>'shade_name',        '')) LIKE :t",
            t: term
          )
        }
      }
      .order(
        Arel.sql(
          "CASE WHEN LOWER(products.material_code) = #{ActiveRecord::Base.connection.quote(q.downcase)} THEN 0
                WHEN LOWER(products.description) LIKE #{ActiveRecord::Base.connection.quote("#{q.downcase}%")} THEN 1
                ELSE 2 END"
        )
      )
      .limit(15)

    stock_map = StockLevel
      .where(organisation_id: @organisation.id, product_id: products.map(&:id))
      .index_by(&:product_id)

    render json: products.map { |p|
      half  = (p.gst_rate.to_f / 2).round(2)
      level = stock_map[p.id]
      {
        id:        p.id,
        label:     p.full_display_name,
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

  def log_sales_activity
    @invoice.sales_invoice_items.each do |item|
      case item.line_type
      when 'paint'
        next unless item.base_product.present?
        per_pack = item.base_product.pack_size_litres ||
                   (TintingMachineCanister.volume_from_pack_code(item.base_product.pack_code) / 1000.0)
        litres   = (item.quantity.to_f * per_pack).round(4)
        ActivityLogger.log(
          organisation:     @invoice.organisation,
          user:             current_user,
          activity_type:    'sales',
          activity_subtype: 'confirmed',
          description:      "Sold #{item.quantity} × #{item.shade_display}",
          quantity_litres:  litres > 0 ? litres : nil,
          reference:        @invoice,
          metadata: {
            invoice_number:  @invoice.invoice_number,
            shade_code:      item.metadata['shade_code'],
            shade_name:      item.metadata['shade_name'],
            base_product_id: item.base_product_id,
            base_name:       item.base_product.display_name,
            pack_code:       item.base_product.pack_code
          }.compact
        )
      when 'product'
        next unless item.product.present?
        ActivityLogger.log(
          organisation:     @invoice.organisation,
          user:             current_user,
          activity_type:    'sales',
          activity_subtype: 'confirmed',
          description:      "Sold #{item.quantity} × #{item.product.display_name}",
          reference:        @invoice,
          metadata: {
            invoice_number: @invoice.invoice_number,
            product_id:     item.product_id,
            material_code:  item.product.material_code
          }.compact
        )
      when 'adhoc'
        next if item.description.blank?
        ActivityLogger.log(
          organisation:     @invoice.organisation,
          user:             current_user,
          activity_type:    'sales',
          activity_subtype: 'confirmed',
          description:      "Sold #{item.quantity} × #{item.description} (adhoc)",
          reference:        @invoice,
          metadata:         { invoice_number: @invoice.invoice_number }
        )
      end
    rescue => e
      Rails.logger.warn("[ActivityLog] sales item #{item.id}: #{e.message}")
    end
  end

  def tinting_brand_id_for_invoice
    paint_items = @invoice.sales_invoice_items
                          .paint_lines
                          .select { |i| i.base_product&.brand_id.present? }
    return nil if paint_items.empty?

    paint_items.group_by { |i| i.base_product.brand_id }
               .max_by { |_, items| items.size }
               &.first
  end

  def tinting_prompt_needed?
    org = @invoice.organisation
    return false unless org.settings['tinting_prompt_enabled']

    threshold = org.settings['tinting_prompt_threshold_litres'].to_f
    return false if threshold <= 0

    total        = org.tinting_litres_since_reset.values.sum
    snooze_until = session[:tinting_snooze_until_litres].to_f
    total >= threshold && (snooze_until <= 0 || total >= snooze_until)
  rescue StandardError
    false
  end

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
      :customer_id, :referrer_id, :invoice_number, :invoice_date, :payment_due_date,
      :payment_mode, :reverse_charge, :status,
      metadata: {},
      sales_invoice_items_attributes: [
        :id, :line_type, :product_id, :shade_catalogue_id,
        :base_product_id, :tinter_product_id,
        :description,
        :quantity, :unit_rate, :discount_percent,
        :taxable_amount, :tax_amount, :total_amount,
        :_destroy,
        metadata: {}
      ]
    )
  end

end