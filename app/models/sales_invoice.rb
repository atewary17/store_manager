# app/models/sales_invoice.rb
class SalesInvoice < ApplicationRecord

  STATUSES      = %w[draft preview confirmed voided].freeze
  PAYMENT_MODES = %w[cash credit upi cheque].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :customer,   optional: true
  belongs_to :user
  belongs_to :voided_by,  class_name: 'User', foreign_key: :voided_by_id, optional: true
  belongs_to :referrer,   optional: true
  has_many   :sales_invoice_items, dependent: :destroy
  has_many   :sale_payments,       dependent: :destroy

  accepts_nested_attributes_for :sales_invoice_items,
    reject_if: ->(attrs) { attrs[:quantity].blank? && attrs[:total_amount].blank? },
    allow_destroy: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :for_org,   ->(org_id) { where(organisation_id: org_id) }
  scope :draft,     -> { where(status: 'draft') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :voided,    -> { where(status: 'voided') }
  scope :active,    -> { where(status: %w[draft confirmed]) }
  scope :recent,    -> { order(created_at: :desc) }
  scope :overdue,   -> { confirmed.where('payment_due_date < ?', Date.today) }

  # ── Validations ───────────────────────────────────────────────
  validates :status,       inclusion: { in: STATUSES }
  validates :invoice_date, presence: true
  validate  :cannot_edit_if_confirmed

  # ── Callbacks ─────────────────────────────────────────────────
  before_validation :coerce_discount

  # ── State helpers ─────────────────────────────────────────────
  def draft?     = status == 'draft'
  def preview?   = status == 'preview'
  def confirmed? = status == 'confirmed'
  def voided?    = status == 'voided'

  def display_number
    invoice_number.presence || "Draft ##{id}"
  end

  def overdue?
    confirmed? && payment_due_date.present? && payment_due_date < Date.today && !fully_paid?
  end

  # ── Live totals ───────────────────────────────────────────────
  def computed_subtotal
    sales_invoice_items.sum(&:total_amount)
  end

  def computed_grand_total
    (computed_subtotal - overall_discount_amount.to_f).round(2)
  end

  def computed_taxable_total
    sales_invoice_items.sum(&:taxable_amount)
  end

  def computed_tax_total
    sales_invoice_items.sum(&:tax_amount)
  end

  # ── Payment helpers ───────────────────────────────────────────
  def total_paid
    sale_payments.sum(:amount).to_f.round(2)
  end

  def outstanding_amount
    (computed_grand_total - total_paid).round(2)
  end

  def fully_paid?
    outstanding_amount <= 0
  end

  def payment_status
    return 'unpaid'   if total_paid == 0
    return 'paid'     if fully_paid?
    'partial'
  end

  # ── Mark as Paid ─────────────────────────────────────────────
  def mark_as_paid!(user, payment_mode: 'cash', notes: 'Marked as fully paid')
    return { success: false, errors: ['Invoice is not confirmed'] } unless confirmed?
    return { success: false, errors: ['Already fully paid'] }       if fully_paid?

    payment = sale_payments.build(
      organisation:  organisation,
      customer_id:   customer_id,
      user:          user,
      payment_date:  Date.today,
      amount:        outstanding_amount,
      payment_mode:  payment_mode,
      notes:         notes
    )

    if payment.save
      { success: true, payment: payment }
    else
      { success: false, errors: payment.errors.full_messages }
    end
  end

  # ── Void ─────────────────────────────────────────────────────
  def void!(current_user)
    return { success: false, errors: ['Only confirmed invoices can be voided'] } unless confirmed?

    reversed_lines = []

    ActiveRecord::Base.transaction do
      sales_invoice_items.each do |item|
        pid = item.paint? ? item.base_product_id.presence : (item.product? ? item.product_id.presence : nil)
        next unless pid

        qty    = item.quantity.to_f
        level  = StockLevel.find_by(organisation: organisation, product_id: pid)
        before = level&.quantity.to_f

        StockLedger.create!(
          organisation:   organisation,
          product_id:     pid,
          user:           current_user,
          entry_type:     'adjustment',
          quantity:       qty,
          unit_cost:      nil,
          notes:          "VOID: Sales Invoice #{display_number}",
          reference_type: 'SalesInvoice',
          reference_id:   id
        )

        after_level = StockLevel.find_by(organisation: organisation, product_id: pid)
        after       = after_level&.quantity&.to_f || (before + qty).round(3)
        product     = Product.find(pid)
        reversed_lines << { product: product.display_name, restored: qty, before: before, after: after }
      end

      self.status    = 'voided'
      self.voided_at = Time.current
      self.voided_by = current_user
      save!
    end

    { success: true, reversed_lines: reversed_lines }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, errors: [e.message] }
  end

  # ── Confirm ───────────────────────────────────────────────────
  def confirm!(current_user)
    return { success: false, errors: ['Already confirmed'] } if confirmed?

    insufficient = []
    sales_invoice_items.each do |item|
      pid = item.paint? ? item.base_product_id.presence : (item.product? ? item.product_id.presence : nil)
      next unless pid

      level     = StockLevel.find_by(organisation: organisation, product_id: pid)
      available = level&.quantity.to_f
      needed    = item.quantity.to_f
      if needed > available
        name = Product.find(pid).display_name rescue "Product ##{pid}"
        insufficient << "#{name}: need #{needed}, only #{[available, 0].max} in stock"
      end
    end
    return { success: false, errors: insufficient } if insufficient.any?

    stock_lines = []
    ActiveRecord::Base.transaction do
      self.total_taxable_amount  = computed_taxable_total
      self.total_tax_amount      = computed_tax_total
      self.total_discount_amount = overall_discount_amount.to_f
      self.total_amount          = computed_grand_total
      self.status                = 'confirmed'
      self.confirmed_at          = Time.current
      save!

      sales_invoice_items.reload.each do |item|
        if item.paint? && item.base_product_id.present?
          sl = deduct_and_record!(item.base_product_id, item.quantity, current_user)
          stock_lines << sl if sl
        elsif item.product? && item.product_id.present?
          sl = deduct_and_record!(item.product_id, item.quantity, current_user)
          stock_lines << sl if sl
        end
      end
    end

    { success: true, stock_lines: stock_lines }
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    { success: false, errors: errors.full_messages }
  end

  private

  def coerce_discount
    self.overall_discount_amount = overall_discount_amount.presence || 0
  end

  # Fields that post-confirmation writes are allowed to touch
  CONFIRM_FIELDS = %w[status confirmed_at voided_at voided_by_id
                      payment_due_date
                      total_taxable_amount total_tax_amount
                      total_discount_amount total_amount].freeze

  def cannot_edit_if_confirmed
    return unless confirmed? || voided?
    return unless changed?
    illegal = changes.keys - CONFIRM_FIELDS
    errors.add(:base, 'Confirmed invoices cannot be edited') if illegal.any?
  end

  def deduct_and_record!(product_id, qty, user)
    qty    = qty.to_f
    return nil if qty <= 0

    level  = StockLevel.find_by(organisation: organisation, product_id: product_id)
    before = level&.quantity.to_f

    StockLedger.create!(
      organisation:   organisation,
      product_id:     product_id,
      user:           user,
      entry_type:     'sale',
      quantity:       -qty,
      unit_cost:      nil,
      notes:          "Sales Invoice #{invoice_number.presence || id}",
      reference_type: 'SalesInvoice',
      reference_id:   id
    )

    after_level = StockLevel.find_by(organisation: organisation, product_id: product_id)
    after       = after_level&.quantity&.to_f || (before - qty).round(3)
    product     = Product.find(product_id)
    { product: product.display_name, deducted: qty, before: before, after: after }
  end

end