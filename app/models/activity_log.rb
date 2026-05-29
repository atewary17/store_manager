class ActivityLog < ApplicationRecord
  belongs_to :organisation
  belongs_to :user, optional: true
  belongs_to :reference, polymorphic: true, optional: true

  ACTIVITY_TYPES = %w[
    sales purchase gst tinting_update stock_adjustment
    invoice_scan user_login product_approval price_list_sync
  ].freeze

  ACTIVITY_SUBTYPES = %w[
    confirmed drafted cancelled updated exported failed
  ].freeze

  validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
  validates :description, presence: true
  validates :expires_at, presence: true

  before_validation :set_expires_at, on: :create

  scope :for_org,     ->(org_id) { where(organisation_id: org_id) }
  scope :today,       -> { where(created_at: Date.current.all_day) }
  scope :for_date,    ->(date) { where(created_at: date.all_day) }
  scope :paint_sales, -> { where(activity_type: 'sales').where.not(quantity_litres: nil) }
  scope :expiring,    -> { where(expires_at: ..Time.current) }

  private

  def set_expires_at
    self.expires_at = Time.current + 90.days
  end
end
