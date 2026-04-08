# app/controllers/api/v1/accounts_controller.rb
#
# GET /api/v1/accounts/payable        — Accounts Payable (purchase side)
# GET /api/v1/accounts/receivable     — Accounts Receivable (sales side)
# GET /api/v1/accounts/payments       — Combined payment ledger (all payments)

class Api::V1::AccountsController < Api::V1::BaseController

  # GET /api/v1/accounts/payable
  # Returns outstanding balances grouped by supplier.
  # Mirrors Purchasing::AccountsPayableController#index logic exactly.
  def payable
    invoices = PurchaseInvoice
      .for_org(@organisation.id)
      .confirmed
      .where.not(supplier_id: nil)
      .includes(:supplier, :purchase_payments)

    by_supplier = invoices.group_by(&:supplier)

    records = by_supplier.filter_map do |supplier, invs|
      total_invoiced = invs.sum(&:total_amount).to_f.round(2)
      total_paid     = invs.sum(&:total_paid).round(2)
      outstanding    = (total_invoiced - total_paid).round(2)
      next if outstanding <= 0

      unpaid_invs   = invs.reject(&:fully_paid?)
      next_due      = unpaid_invs.map(&:payment_due_date).compact.min
      overdue       = next_due.present? && next_due < Date.today

      {
        supplier: {
          id:    supplier.id,
          name:  supplier.name,
          gstin: supplier.gstin,
          state: supplier.state
        },
        invoice_count:   invs.size,
        total_invoiced:  total_invoiced,
        total_paid:      total_paid,
        outstanding:     outstanding,
        next_due_date:   next_due&.iso8601,
        overdue:         overdue,
        overdue_count:   unpaid_invs.count { |i| i.payment_due_date.present? && i.payment_due_date < Date.today },
        last_invoice_at: invs.map(&:invoice_date).compact.max&.iso8601
      }
    end

    records.sort_by! { |r| [r[:overdue] ? 0 : 1, r[:next_due_date] || '9999-12-31'] }

    render_success(
      accounts_payable:  records,
      summary: {
        total_outstanding: records.sum { |r| r[:outstanding] }.round(2),
        supplier_count:    records.size,
        overdue_count:     records.count { |r| r[:overdue] }
      }
    )
  end

  # GET /api/v1/accounts/receivable
  # Returns outstanding balances grouped by customer.
  def receivable
    invoices = SalesInvoice
      .for_org(@organisation.id)
      .confirmed
      .includes(:customer, :sale_payments)

    by_customer = invoices.group_by { |i| i.customer || :walk_in }

    records = by_customer.filter_map do |customer, invs|
      total_invoiced = invs.sum(&:total_amount).to_f.round(2)
      total_paid     = invs.sum(&:total_paid).round(2)
      outstanding    = (total_invoiced - total_paid).round(2)
      next if outstanding <= 0

      unpaid_invs = invs.reject(&:fully_paid?)
      overdue_invs = unpaid_invs.select(&:overdue?)

      {
        customer: customer == :walk_in ? { id: nil, name: 'Walk-in', gstin: nil, state: nil } : {
          id:    customer.id,
          name:  customer.name,
          gstin: customer.gstin,
          state: customer.state,
          phone: customer.phone
        },
        invoice_count:   invs.size,
        total_invoiced:  total_invoiced,
        total_paid:      total_paid,
        outstanding:     outstanding,
        overdue:         overdue_invs.any?,
        overdue_count:   overdue_invs.size,
        last_invoice_at: invs.map(&:invoice_date).compact.max&.iso8601
      }
    end

    records.sort_by! { |r| [r[:overdue] ? 0 : 1, -r[:outstanding]] }

    render_success(
      accounts_receivable: records,
      summary: {
        total_outstanding: records.sum { |r| r[:outstanding] }.round(2),
        customer_count:    records.size,
        overdue_count:     records.count { |r| r[:overdue] }
      }
    )
  end

  # GET /api/v1/accounts/payments
  # Combined ledger: all purchase payments + all sale payments in one timeline.
  # Optional filters: ?type=purchase|sale&from=2026-01-01&to=2026-03-31&page=1
  def payments
    purchase_payments = []
    sale_payments     = []

    unless params[:type] == 'sale'
      purchase_payments = PurchasePayment
        .for_org(@organisation.id)
        .includes(:supplier, :purchase_invoice)
        .recent

      if params[:from].present?
        purchase_payments = purchase_payments.where('payment_date >= ?', params[:from])
      end
      if params[:to].present?
        purchase_payments = purchase_payments.where('payment_date <= ?', params[:to])
      end

      purchase_payments = purchase_payments.map { |p|
        {
          type:           'purchase_payment',
          id:             p.id,
          payment_number: p.payment_label,
          amount:         p.amount.to_f,
          payment_date:   p.payment_date&.iso8601,
          payment_mode:   p.payment_mode,
          direction:      'outflow',
          party: {
            type:  'supplier',
            id:    p.supplier&.id,
            name:  p.supplier&.name
          },
          invoice: {
            id:     p.purchase_invoice&.id,
            number: p.purchase_invoice&.display_number
          },
          notes:       p.notes,
          created_at:  p.created_at.iso8601
        }
      }
    end

    unless params[:type] == 'purchase'
      sale_payments = SalePayment
        .for_org(@organisation.id)
        .includes(:customer, :sales_invoice)
        .recent

      if params[:from].present?
        sale_payments = sale_payments.where('payment_date >= ?', params[:from])
      end
      if params[:to].present?
        sale_payments = sale_payments.where('payment_date <= ?', params[:to])
      end

      sale_payments = sale_payments.map { |p|
        {
          type:           'sale_receipt',
          id:             p.id,
          payment_number: p.receipt_label,
          amount:         p.amount.to_f,
          payment_date:   p.payment_date&.iso8601,
          payment_mode:   p.payment_mode,
          direction:      'inflow',
          party: {
            type:  'customer',
            id:    p.customer&.id,
            name:  p.customer&.name || 'Walk-in'
          },
          invoice: {
            id:     p.sales_invoice&.id,
            number: p.sales_invoice&.display_number
          },
          created_at:  p.created_at.iso8601
        }
      }
    end

    # Merge and sort by date descending
    all_payments = (purchase_payments + sale_payments)
      .sort_by { |p| p[:payment_date] || '0000-00-00' }
      .reverse

    total_inflow  = all_payments.select { |p| p[:direction] == 'inflow' }.sum { |p| p[:amount] }
    total_outflow = all_payments.select { |p| p[:direction] == 'outflow' }.sum { |p| p[:amount] }

    render_success(
      payments: all_payments,
      summary: {
        total_payments: all_payments.size,
        total_inflow:   total_inflow.round(2),
        total_outflow:  total_outflow.round(2),
        net_cashflow:   (total_inflow - total_outflow).round(2)
      }
    )
  end

end
