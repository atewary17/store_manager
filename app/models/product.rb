class Product < ApplicationRecord
  belongs_to :product_category
  belongs_to :base_uom, class_name: 'Uom', foreign_key: :base_uom_id

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered,  -> { order(:brand, :description) }

  GST_RATES = [0.0, 5.0, 12.0, 18.0, 28.0].freeze

  validates :brand,        presence: true
  validates :description,  presence: true
  validates :gst_rate,     inclusion: { in: GST_RATES,
                             message: "must be one of: #{GST_RATES.join(', ')}%" }
  validates :product_category, presence: true
  validates :base_uom,         presence: true
  validates :material_code, uniqueness: true, allow_blank: true
  validates :product_code,  uniqueness: true, allow_blank: true

  before_save :strip_whitespace
  before_save :nullify_blank_codes

  def display_name
    parts = [brand, pack_code, description].compact_blank
    parts.join(' — ')
  end

  def full_code
    [material_code, product_code].compact_blank.join(' / ')
  end

  private

  def strip_whitespace
    %i[brand material_code product_code pack_code hsn_code].each do |field|
      self[field] = self[field].strip if self[field].present?
    end
  end

  def nullify_blank_codes
    self.material_code = nil if material_code.blank?
    self.product_code  = nil if product_code.blank?
  end
end
