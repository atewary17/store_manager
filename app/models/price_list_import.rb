# app/models/price_list_import.rb
class PriceListImport < ApplicationRecord

  belongs_to :user

  scope :recent,      -> { order(created_at: :desc) }
  scope :pending,     -> { where(status: 'pending') }
  scope :processing,  -> { where(status: 'processing') }
  scope :done,        -> { where(status: 'done') }
  scope :failed,      -> { where(status: 'failed') }

  def pending?    = status == 'pending'
  def processing? = status == 'processing'
  def done?       = status == 'done'
  def failed?     = status == 'failed'
  def in_progress? = pending? || processing?

  def has_errors?
    error_count.to_i > 0
  end

  def file_size_human
    return '—' unless file_size.to_i > 0
    if file_size < 1024
      "#{file_size} B"
    elsif file_size < 1_048_576
      "#{(file_size / 1024.0).round(1)} KB"
    else
      "#{(file_size / 1_048_576.0).round(1)} MB"
    end
  end

end
