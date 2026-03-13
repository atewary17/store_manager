# app/models/digitise_import.rb
class DigitiseImport < ApplicationRecord

  STATUSES = %w[pending processing retrying review confirmed failed stopped].freeze

  belongs_to :organisation
  belongs_to :user
  belongs_to :purchase_invoice, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :for_org,  ->(org_id) { where(organisation_id: org_id) }

  def attempt_log
    self[:attempt_log] || []
  end
  scope :recent,   -> { order(created_at: :desc) }
  scope :pending,  -> { where(status: 'pending') }
  scope :review,   -> { where(status: 'review') }

  def file_size_human
    return '—' unless file_size.present?
    if file_size < 1024
      "#{file_size} B"
    elsif file_size < 1_048_576
      "#{(file_size / 1024.0).round(1)} KB"
    else
      "#{(file_size / 1_048_576.0).round(1)} MB"
    end
  end

  def pdf?
    file_content_type == 'application/pdf'
  end

  def image?
    file_content_type&.start_with?('image/')
  end

  # Convenience accessors into parsed_data
  def parsed_header
    parsed_data['header'] || {}
  end

  def parsed_items
    parsed_data['items'] || []
  end

  def parsed_supplier
    parsed_data['supplier'] || {}
  end
end