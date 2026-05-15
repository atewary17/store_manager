class ApplicationController < ActionController::Base
  layout :set_layout

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