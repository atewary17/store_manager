class ApplicationController < ActionController::Base
  layout :set_layout

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to dashboard_path, alert: 'Access denied. You do not have permission to access this page.'
  end

  before_action :set_pending_inbox_count

  private

  def set_pending_inbox_count
    return unless user_signed_in?
    return unless current_user.admin? || current_user.super_admin?
    org = current_user.organisation
    return unless org
    @pending_inbox_count = ProductInboxItem
                             .where(organisation: org, status: %w[pending needs_review])
                             .count
  rescue
    @pending_inbox_count = 0
  end

  def set_layout
    devise_controller? ? 'devise' : 'application'
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end
end