# app/controllers/sales/referrers_controller.rb
class Sales::ReferrersController < Sales::BaseController

  before_action :set_referrer, only: [:show, :edit, :update, :destroy]

  # GET /sales/referrers
  def index
    @referrers = Referrer.for_org(@organisation.id).ordered.includes(:sales_invoices)

    # Filter by trade
    @referrers = @referrers.by_trade(params[:trade]) if params[:trade].present?

    # Filter active/inactive
    @referrers = params[:status] == 'inactive' ? @referrers.where(active: false) : @referrers.active

    # Summary stats
    @total_count        = @referrers.count
    @total_referred     = SalesInvoice.confirmed
                            .where(organisation: @organisation)
                            .where.not(referrer_id: nil)
                            .sum(:total_amount).to_f.round(2)
    @invoices_with_ref  = SalesInvoice.confirmed
                            .where(organisation: @organisation)
                            .where.not(referrer_id: nil).count
    @top_referrer       = @referrers.max_by(&:total_referred_amount)
  end

  # GET /sales/referrers/:id
  def show
    @invoices = @referrer.sales_invoices
                          .confirmed
                          .includes(:customer, :sale_payments)
                          .order(invoice_date: :desc)
                          .limit(20)

    @total_amount      = @referrer.total_referred_amount
    @total_outstanding = @referrer.total_outstanding
    @invoice_count     = @referrer.total_invoices
    @last_referral     = @referrer.last_referral_date
  end

  # GET /sales/referrers/new
  def new
    @referrer = Referrer.new(organisation: @organisation, trade: 'painter')
  end

  # POST /sales/referrers
  def create
    @referrer = Referrer.new(referrer_params)
    @referrer.organisation = @organisation

    if @referrer.save
      redirect_to sales_referrer_path(@referrer),
        notice: "#{@referrer.name} added as a referrer."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /sales/referrers/:id/edit
  def edit; end

  # PATCH /sales/referrers/:id
  def update
    if @referrer.update(referrer_params)
      redirect_to sales_referrer_path(@referrer),
        notice: 'Referrer updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /sales/referrers/:id
  def destroy
    if @referrer.can_delete?
      @referrer.destroy
      redirect_to sales_referrers_path, notice: 'Referrer removed.'
    else
      redirect_to sales_referrer_path(@referrer),
        alert: 'Cannot delete — this referrer is linked to sales invoices. Deactivate instead.'
    end
  end

  # GET /sales/referrers/search?q=...  (for AJAX dropdown on sales invoice form)
  def search
    q = params[:q].to_s.strip
    return render json: [] if q.length < 1

    referrers = Referrer.for_org(@organisation.id).active
                        .where('LOWER(name) LIKE :q OR phone LIKE :q',
                               q: "%#{q.downcase}%")
                        .ordered.limit(10)

    render json: referrers.map { |r|
      { id: r.id, name: r.name, phone: r.phone, trade: r.display_trade,
        label: "#{r.name} — #{r.display_trade}#{r.phone.present? ? " · #{r.phone}" : ''}" }
    }
  end

  private

  def set_referrer
    @referrer = Referrer.for_org(@organisation.id).find(params[:id])
  end

  def referrer_params
    params.require(:referrer).permit(
      :name, :phone, :trade, :address, :area, :active,
      metadata: {}
    )
  end

end
