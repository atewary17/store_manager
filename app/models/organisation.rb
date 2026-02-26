class Organisation < ApplicationRecord
  has_many :users, dependent: :destroy

  enum status: { active: 0, inactive: 1 }

  validates :name, presence: true
  validates :gst_number, uniqueness: true, allow_blank: true

  scope :active, -> { where(status: :active) }
end