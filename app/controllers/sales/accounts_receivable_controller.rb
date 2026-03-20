# app/controllers/sales/accounts_receivable_controller.rb
# Accounts Receivable — Outstanding customer payments.
# Lists customers (debtors) who owe money on confirmed sales invoices.
class Sales::AccountsReceivableController < Sales::BaseController

  # GET /sales/accounts_receivable
  # Lists customers who have at least one confirmed invoice with outstanding balance.
  # Walk-in invoices (customer_id IS NULL) are excluded.
  def index
    # All confirmed invoices for this org with a named customer
    invoices = SalesInvoice
      .for_org(@organisation.id)
      .confirmed
      .where.not(customer_id: nil)
      .includes(:customer, :sale_payments)

    # Group by customer and compute totals
    by_customer = invoices.group_by(&:customer)

    @ar_records = by_customer.filter_map do |customer, invs|
      total_invoiced   = invs.sum(&:computed_grand_total).round(2)
      total_collected  = invs.sum(&:total_paid).round(2)
      outstanding      = (total_invoiced - total_collected).round(2)
      next if outstanding <= 0   # fully settled — skip

      # Earliest due date among unpaid invoices for this customer
      unpaid_invs   = invs.reject(&:fully_paid?)
      due_dates     = unpaid_invs.map(&:payment_due_date).compact
      next_due_date = due_dates.min
      overdue       = next_due_date.present? && next_due_date < Date.today

      {
        customer:        customer,
        invoice_count:   invs.size,
        total_invoiced:  total_invoiced,
        total_collected: total_collected,
        outstanding:     outstanding,
        last_invoice_at: invs.map(&:invoice_date).compact.max,
        next_due_date:   next_due_date,
        overdue:         overdue,
        overdue_count:   unpaid_invs.count { |i| i.payment_due_date.present? && i.payment_due_date < Date.today }
      }
    end

    # Sort by highest outstanding first
    @ar_records.sort_by! { |c| -c[:outstanding] }
    render 'sales/accounts_receivable/index'
  end

  # GET /sales/accounts_receivable/:id   — customer ledger
  def show
    @customer = Customer.for_org(@organisation.id).find(params[:id])

    @invoices = SalesInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(customer: @customer)
      .includes(:sales_invoice_items, :sale_payments)
      .order(invoice_date: :desc)

    @payments = SalePayment
      .for_org(@organisation.id)
      .for_customer(@customer.id)
      .includes(:sales_invoice)
      .chronological

    @total_invoiced   = @invoices.sum(&:computed_grand_total).round(2)
    @total_collected  = @invoices.sum(&:total_paid).round(2)
    @total_outstanding = (@total_invoiced - @total_collected).round(2)
    render 'sales/accounts_receivable/show'
  end

end