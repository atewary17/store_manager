class ApplicationController < ActionController::Base
  layout :set_layout

  private

  def set_layout
    devise_controller? ? 'devise' : 'application'
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end
end