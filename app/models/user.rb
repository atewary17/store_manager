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


  # ── Preferences (jsonb column — added by migration 20260322000002) ──────────
  # Stores per-user settings: ai_provider, theme, future preferences
  # Defaults to {} — always returns a hash, never nil
  def preferences
    read_attribute(:preferences) || {}
  end

  # Convenience helpers
  def preferred_ai_provider
    preferences['ai_provider'].presence
  end

  def effective_ai_provider
    preferred_ai_provider || ENV['INVOICE_AI_PROVIDER'] || 'gemini'
  end

  # ── Single-session enforcement ────────────────────────────────────────────
  SESSION_IDLE_THRESHOLD = 30.minutes

  def active_elsewhere?
    session_token.present? &&
      last_activity_at.present? &&
      last_activity_at > SESSION_IDLE_THRESHOLD.ago
  end

  def idle_elsewhere?
    session_token.present? &&
      (last_activity_at.blank? || last_activity_at <= SESSION_IDLE_THRESHOLD.ago)
  end

  def generate_session_token!
    update_columns(session_token: SecureRandom.hex(32), last_activity_at: Time.current)
    session_token
  end

  def clear_session_token!
    update_columns(session_token: nil, last_activity_at: nil)
  end

  def touch_activity!
    update_columns(last_activity_at: Time.current)
  end
end