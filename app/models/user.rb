# app/models/user.rb
class User < ApplicationRecord
  belongs_to :organisation, optional: true

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role:   { staff: 0, admin: 1, owner: 2, super_admin: 3 }
  enum status: { active: 0, inactive: 1 }

  validates :email, presence: true, uniqueness: true
  validates :role,  presence: true

  scope :active, -> { where(status: :active) }

  def full_name
    [first_name, last_name].compact_blank.join(' ').presence || email.split('@').first
  end

  def initials
    if first_name.present? && last_name.present?
      "#{first_name[0]}#{last_name[0]}".upcase
    else
      email[0].upcase
    end
  end

  def super_admin?
    role == 'super_admin'
  end
end