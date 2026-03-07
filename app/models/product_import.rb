# app/models/product_import.rb
class ProductImport < ApplicationRecord
  belongs_to :organisation
  belongs_to :user

  STATUSES = %w[pending processing done failed].freeze

  validates :file_name, presence: true
  validates :status,    inclusion: { in: STATUSES }

  scope :recent,      -> { order(created_at: :desc) }
  scope :for_org,     ->(org) { where(organisation: org) }

  def pending?;    status == 'pending';    end
  def processing?; status == 'processing'; end
  def done?;       status == 'done';       end
  def failed?;     status == 'failed';     end

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