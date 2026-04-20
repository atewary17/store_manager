class ProductAlias < ApplicationRecord

  belongs_to :organisation
  belongs_to :product

  SOURCES = %w[exact fuzzy hsn ai admin].freeze

  validates :source,          inclusion: { in: SOURCES }
  validates :raw_text,        presence: true
  validates :normalised_text, presence: true,
                              uniqueness: { scope: :organisation_id }
  validates :confidence,      numericality: { in: 0.0..1.0 }

  scope :for_org, ->(org_id) { where(organisation_id: org_id) }

  def self.normalise(text)
    text.to_s.downcase.strip.gsub(/\s+/, ' ').gsub(/[^\w\s]/, '').strip
  end

end
