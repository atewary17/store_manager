class ApplicationController < ActionController::Base
  layout :set_layout

  before_action :validate_session_token
  before_action :touch_last_activity

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to dashboard_path, alert: 'Access denied. You do not have permission to access this page.'
  end

  helper_method :tinting_badge_needed?

  def tinting_badge_needed?
    return @_tinting_badge_needed if defined?(@_tinting_badge_needed)
    @_tinting_badge_needed = begin
      return false unless user_signed_in?
      org = current_user.organisation
      return false unless org&.settings&.dig('tinting_prompt_enabled')

      threshold = org.settings['tinting_prompt_threshold_litres'].to_f
      return false if threshold <= 0

      total = org.tinting_litres_since_reset.values.sum
      return false if total < threshold

      snooze_until = session[:tinting_snooze_until_litres].to_f
      snooze_until <= 0 || total >= snooze_until
    rescue StandardError
      false
    end
  end

  private

  def set_layout
    devise_controller? ? 'devise' : 'application'
  end

  # Compares the browser session token against the DB. Mismatch means someone
  # signed in on another device and invalidated this session.
  def validate_session_token
    return unless user_signed_in?
    return if devise_controller?

    stored = session[:session_token]

    if stored.blank?
      # Legacy session (pre-feature deploy) — only reject if DB has a token,
      # meaning a newer session exists elsewhere.
      if current_user.session_token.present?
        sign_out(current_user)
        redirect_to new_user_session_path,
                    alert: 'Please sign in again to continue.'
      end
      return
    end

    unless stored == current_user.session_token
      sign_out(current_user)
      redirect_to new_user_session_path,
                  alert: 'You were signed in from another device. Please log in again.'
    end
  end

  # Throttled heartbeat — writes last_activity_at at most once every 2 minutes.
  def touch_last_activity
    return unless user_signed_in?
    return if devise_controller?

    # Backfill token for sessions that existed before this feature was deployed.
    if session[:session_token].blank? && current_user.session_token.blank?
      token = current_user.generate_session_token!
      session[:session_token] = token
    end

    return if current_user.last_activity_at.present? &&
              current_user.last_activity_at > 2.minutes.ago

    current_user.touch_activity!
  end

  def after_sign_in_path_for(resource)
    begin
      ActivityLogger.log(
        organisation:     resource.organisation,
        user:             resource,
        activity_type:    'user_login',
        activity_subtype: 'sign_in',
        description:      "User signed in — #{resource.email}",
        reference:        resource,
        metadata:         { email: resource.email, role: resource.role }.compact
      )
    rescue => e
      Rails.logger.warn("[ActivityLog] user_login #{resource.id}: #{e.message}")
    end
    dashboard_path
  end
end