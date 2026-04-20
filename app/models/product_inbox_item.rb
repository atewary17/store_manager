class ProductInboxItem < ApplicationRecord

  STATUSES = %w[pending ai_processing needs_review approved mapped ignored].freeze

  belongs_to :organisation
  belongs_to :purchase_invoice_item, optional: true
  belongs_to :resolved_product,  class_name: 'Product', optional: true,
                                  foreign_key: :resolved_product_id
  belongs_to :resolved_by,       class_name: 'User',    optional: true,
                                  foreign_key: :resolved_by_id

  validates :raw_invoice_text, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_org,   ->(org) { where(organisation: org) }
  scope :pending,   -> { where(status: 'pending') }
  scope :unresolved, -> { where.not(status: %w[approved mapped ignored]) }

end
