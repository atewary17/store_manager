# app/controllers/setup/base_controller.rb
class Setup::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_setup_access!

  private

  # Only super_admin, owner, admin can access setup/master data
  def authorize_setup_access!
    unless current_user.super_admin? || current_user.owner? || current_user.admin?
      redirect_to dashboard_path, alert: 'Access denied. Setup requires admin or above.'
    end
  end
end
