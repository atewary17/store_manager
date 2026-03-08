# app/controllers/purchasing/base_controller.rb
class Purchasing::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation

  private

  def set_organisation
    if current_user.super_admin? && params[:organisation_id].present?
      @organisation = Organisation.find(params[:organisation_id])
    else
      @organisation = current_user.organisation
    end
    redirect_to dashboard_path, alert: 'No organisation found.' unless @organisation
  end
end
