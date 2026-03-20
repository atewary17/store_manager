# app/controllers/setup/base_controller.rb
class Setup::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_setup_access!
  before_action :set_organisation

  private

  # Only super_admin, owner, admin can access setup/master data
  def authorize_setup_access!
    unless current_user.super_admin? || current_user.owner? || current_user.admin?
      redirect_to dashboard_path, alert: 'Access denied. Setup requires admin or above.'
    end
  end

  def set_organisation
    if current_user.super_admin? && params[:organisation_id].present?
      @organisation = Organisation.find(params[:organisation_id])
    else
      @organisation = current_user.organisation
    end
    # super_admin browsing master data without an org context is fine —
    # they see global views. Only redirect if a non-super_admin has no org.
    if @organisation.nil? && !current_user.super_admin?
      redirect_to dashboard_path, alert: 'No organisation found.'
    end
  end
end