# app/controllers/purchasing/accounts_payable_controller.rb
# Accounts Payable — suppliers you owe money to.
# Shows confirmed purchase invoices with outstanding balances,
# grouped by supplier, ordered by due date.
class Purchasing::AccountsPayableController < Purchasing::BaseController

  # GET /purchasing/accounts_payable
  def index
    invoices = PurchaseInvoice
      .for_org(@organisation.id)
      .confirmed
      .where.not(supplier_id: nil)
      .includes(:supplier, :purchase_payments)

    by_supplier = invoices.group_by(&:supplier)

    @ap_records = by_supplier.filter_map do |supplier, invs|
      total_invoiced  = invs.sum(&:total_amount).to_f.round(2)
      total_paid      = invs.sum(&:total_paid).round(2)
      outstanding     = (total_invoiced - total_paid).round(2)
      next if outstanding <= 0

      unpaid_invs   = invs.reject(&:fully_paid?)
      due_dates     = unpaid_invs.map(&:payment_due_date).compact
      next_due_date = due_dates.min
      overdue       = next_due_date.present? && next_due_date < Date.today

      {
        supplier:        supplier,
        invoice_count:   invs.size,
        total_invoiced:  total_invoiced,
        total_paid:      total_paid,
        outstanding:     outstanding,
        last_invoice_at: invs.map(&:invoice_date).compact.max,
        next_due_date:   next_due_date,
        overdue:         overdue,
        overdue_count:   unpaid_invs.count { |i| i.payment_due_date.present? && i.payment_due_date < Date.today }
      }
    end

    @ap_records.sort_by! { |r| [r[:overdue] ? 0 : 1, r[:next_due_date] || Date.new(9999)] }

    @total_outstanding  = @ap_records.sum { |r| r[:outstanding] }
    @overdue_count      = @ap_records.count { |r| r[:overdue] }
    @supplier_count     = @ap_records.size
  end

  # GET /purchasing/accounts_payable/:id  — supplier ledger
  def show
    @supplier = Supplier.where(organisation: @organisation).find(params[:id])

    @invoices = PurchaseInvoice
      .for_org(@organisation.id)
      .confirmed
      .where(supplier: @supplier)
      .includes(:purchase_invoice_items, :purchase_payments)
      .order(invoice_date: :desc)

    @payments = PurchasePayment
      .for_org(@organisation.id)
      .for_supplier(@supplier.id)
      .includes(:purchase_invoice)
      .chronological

    @total_invoiced    = @invoices.sum(&:total_amount).to_f.round(2)
    @total_paid        = @invoices.sum(&:total_paid).round(2)
    @total_outstanding = (@total_invoiced - @total_paid).round(2)
  end

end
