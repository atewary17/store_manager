# app/models/price_list_import.rb
class PriceListImport < ApplicationRecord

  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }

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
