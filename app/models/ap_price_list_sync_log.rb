# app/models/ap_price_list_sync_log.rb
class ApPriceListSyncLog < ApplicationRecord

  MATCH_STATUSES = %w[matched partial ambiguous unmatched already_matched save_failed].freeze
  CONFIDENCES    = %w[high medium low none].freeze

  belongs_to :product
  belongs_to :run_by, class_name: 'User', optional: true, foreign_key: :run_by_id

  scope :recent,        -> { order(run_at: :desc) }
  scope :matched,       -> { where(match_status: 'matched') }
  scope :unmatched,     -> { where(match_status: 'unmatched') }
  scope :for_product,   ->(p) { where(product: p) }
  scope :for_run_at,    ->(range) { where(run_at: range) }
  scope :high_conf,     -> { where(confidence: 'high') }

end
