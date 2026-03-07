class ApplicationController < ActionController::Base
  layout :set_layout

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to dashboard_path, alert: 'Access denied. You do not have permission to access this page.'
  end

  private

  def set_layout
    devise_controller? ? 'devise' : 'application'
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end
end