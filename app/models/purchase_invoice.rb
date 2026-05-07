# app/models/purchase_invoice.rb
class PurchaseInvoice < ApplicationRecord

  STATUSES = %w[draft confirmed].freeze

  # ── Associations ─────────────────────────────────────────────
  belongs_to :organisation
  belongs_to :supplier,     optional: true
  belongs_to :user
  has_many   :purchase_invoice_items, dependent: :destroy
  has_many   :purchase_payments,       dependent: :destroy

  accepts_nested_attributes_for :purchase_invoice_items,
    reject_if: ->(attrs) { attrs[:quantity].blank? && attrs[:total_amount].blank? },
    allow_destroy: true

  # ── Scopes ───────────────────────────────────────────────────
  scope :draft,     -> { where(status: 'draft') }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :recent,    -> { order(created_at: :desc) }
  scope :for_org,   ->(org_id) { where(organisation_id: org_id) }

  # ── Validations ───────────────────────────────────────────────
  validates :status, inclusion: { in: STATUSES }
  validates :delivery_date, presence: true
  validates :invoice_number,
            uniqueness: { scope: :organisation_id, message: 'already exists for this organisation' },
            allow_blank: true
  validate  :cannot_edit_if_confirmed

  # ── Confirm ───────────────────────────────────────────────────
  def confirm!(current_user)
    if confirmed?
      errors.add(:base, 'Already confirmed')
      return false
    end

    new_products = []

    ActiveRecord::Base.transaction do
      # Compute totals from items
      # Recompute unit_rate = total_amount / quantity for each item
      purchase_invoice_items.each do |item|
        qty   = item.quantity.to_f
        total = item.total_amount.to_f
        item.unit_rate = (qty > 0 && total > 0) ? (total / qty).round(4) : 0

        # ── GST: use new gst_rate column (from product), fall back to old metadata keys ──
        # New form saves gst_rate via gst-rate-input hidden field in metadata temporarily;
        # prefer product.gst_rate as the authoritative source.
        rate = item.product&.gst_rate.to_f
        rate = item.metadata['gst_rate'].to_f        if rate.zero? && item.metadata['gst_rate'].present?
        rate = (item.metadata['cgst_percent'].to_f +
                item.metadata['sgst_percent'].to_f +
                item.metadata['igst_percent'].to_f)   if rate.zero?

        disc_pct  = item.metadata['discount_percent'].to_f
        taxable   = rate > 0 ? (total / (1 + rate / 100.0)).round(2) : total
        tax_amt   = (total - taxable).round(2)

        # Intra-state split (CGST + SGST) vs inter-state (IGST)
        # Determined by comparing organisation state with supplier state.
        # Defaults to intra-state (CGST+SGST) if states unavailable.
        is_igst   = self.supplier&.state.present? &&
                    self.organisation&.state.present? &&
                    self.supplier.state.strip.downcase !=
                      self.organisation.state.strip.downcase

        cgst_pct  = is_igst ? 0 : (rate / 2.0).round(2)
        sgst_pct  = is_igst ? 0 : (rate / 2.0).round(2)
        igst_pct  = is_igst ? rate : 0

        # ── Compute per-head GST amounts ─────────────────────────────────────
        computed_cgst = is_igst ? 0 : (taxable * cgst_pct / 100.0).round(2)
        computed_sgst = is_igst ? 0 : (taxable * sgst_pct / 100.0).round(2)
        computed_igst = is_igst ? (taxable * igst_pct / 100.0).round(2) : 0
        supply        = is_igst ? 'inter_state' : 'intra_state'

        # ── Write proper decimal columns (source of truth) ────────────────
        item.gst_rate        = rate
        item.taxable_amount  = taxable
        item.tax_amount      = tax_amt
        item.discount_percent = disc_pct
        item.discount_amount  = disc_pct > 0 ?
          ((taxable / (1 - disc_pct / 100.0)) * (disc_pct / 100.0)).round(2) : 0
        item.supply_type     = supply
        item.cgst_amount     = computed_cgst
        item.sgst_amount     = computed_sgst
        item.igst_amount     = computed_igst

        # ── Keep metadata in sync for backward compat ────────────────────
        item.metadata = item.metadata.merge(
          'gst_rate'       => rate,
          'taxable_amount' => taxable,
          'cgst_percent'   => cgst_pct,
          'sgst_percent'   => sgst_pct,
          'igst_percent'   => igst_pct,
          'cgst_amount'    => computed_cgst,
          'sgst_amount'    => computed_sgst,
          'igst_amount'    => computed_igst,
          'supply_type'    => supply
        )
        item.save!
      end

      # Aggregate totals from new proper columns
      self.total_taxable_amount = purchase_invoice_items.sum(&:taxable_amount)
      self.total_tax_amount     = purchase_invoice_items.sum(&:tax_amount)
      self.total_amount         = purchase_invoice_items.sum(&:total_amount)
      self.status           = 'confirmed'
      self.confirmed_at     = Time.current
      save!

      # ── Auto-create products for items still missing a product_id ───────────
      # Runs after GST loop so all item financials are already saved.
      # UnmatchedProductCreator creates an under_review product + organisation_product,
      # then stamps product_id on the item so the stock ledger loop below picks it up.
      purchase_invoice_items.where(product_id: nil, unmatched: true).each do |item|
        product = UnmatchedProductCreator.call(item: item, organisation: organisation)
        new_products << product
      end

      # Create stock ledger entries for ALL items that have a product_id.
      # Must use a SQL WHERE (not Ruby select) — the AR association cache still holds
      # the pre-UnmatchedProductCreator in-memory objects with product_id: nil,
      # so a Ruby-level filter would silently skip the newly created products.
      purchase_invoice_items.where.not(product_id: nil).each do |item|
        StockLedger.create!(
          organisation:   organisation,
          product_id:     item.product_id,
          user:           current_user,
          entry_type:     'purchase',
          quantity:       item.quantity,
          unit_cost:      item.unit_rate,
          notes:          "Purchase Invoice #{invoice_number.presence || id}" \
                          "#{item.unmatched? ? ' [pending product — awaiting admin review]' : ''}",
          reference_type: 'PurchaseInvoice',
          reference_id:   id
        )
      end
    end

    # Enqueue AI enrichment for each newly created under_review product.
    # Must run AFTER the transaction commits — jobs must not fire before the
    # product row is visible to the job worker.
    new_products.compact.each do |product|
      EnrichUnmatchedProductJob.perform_later(product.id)
    end

    # Notify SuperAdmin if any unmatched products were created.
    if new_products.any?
      ProductReviewMailer.new_unmatched_products(
        products:         new_products.compact,
        organisation:     organisation,
        purchase_invoice: self
      ).deliver_later
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  # ── Helpers ───────────────────────────────────────────────────
  def draft?
    status == 'draft'
  end

  def confirmed?
    status == 'confirmed'
  end

  def unmatched_count
    purchase_invoice_items.where(unmatched: true).count
  end

  def display_number
    invoice_number.presence || "Draft ##{id}"
  end

  # ── Duplicate item guard (used in append/session mode) ──────
  #
  # Checks whether any of the candidate items already exist in this invoice.
  # Match criteria: same material_code + same quantity + same total_amount (±0.01).
  # Returns an array of duplicate item hashes (empty = no duplicates).
  #
  def duplicate_items(candidate_items)
    existing = purchase_invoice_items.map do |i|
      {
        material_code: i.metadata['material_code'].to_s.strip,
        quantity:      i.quantity.to_f,
        total_amount:  i.total_amount.to_f,
        description:   i.metadata['description'].to_s
      }
    end

    candidate_items.select do |new_item|
      code  = new_item['material_code'].to_s.strip
      qty   = new_item['quantity'].to_f
      total = new_item['total_amount'].to_f
      next false if code.blank? && qty.zero? && total.zero?

      existing.any? do |e|
        e[:material_code] == code &&
        (e[:quantity]     - qty).abs   < 0.001 &&
        (e[:total_amount] - total).abs < 0.01
      end
    end
  end

  def has_duplicate_items?(candidate_items)
    duplicate_items(candidate_items).any?
  end

  # ── Payment helpers ─────────────────────────────────────────
  def total_paid
    purchase_payments.sum(:amount).to_f.round(2)
  end

  def outstanding_amount
    (total_amount.to_f - total_paid).round(2)
  end

  def fully_paid?
    outstanding_amount <= 0
  end

  def overdue?
    payment_due_date.present? && payment_due_date < Date.today && !fully_paid?
  end

  def payment_status
    if fully_paid?
      'paid'
    elsif total_paid > 0
      'partial'
    else
      'unpaid'
    end
  end

  private

  # Fields that confirm! is allowed to write on a confirmed record
  CONFIRM_FIELDS = %w[status confirmed_at total_taxable_amount total_tax_amount total_amount payment_due_date].freeze

  def cannot_edit_if_confirmed
    return unless confirmed?
    return unless changed?
    # Allow the transition itself (draft → confirmed) and the aggregate fields confirm! sets
    illegal = changes.keys - CONFIRM_FIELDS
    if illegal.any?
      errors.add(:base, 'Confirmed invoices cannot be edited')
    end
  end

end