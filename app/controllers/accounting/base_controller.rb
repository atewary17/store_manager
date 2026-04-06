# app/controllers/accounting/base_controller.rb
class Accounting::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation

  private

  def set_organisation
    @organisation = current_user.organisation
  end
end
