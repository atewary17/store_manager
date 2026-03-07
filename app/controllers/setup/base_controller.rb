# app/controllers/setup/base_controller.rb
class Setup::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_setup_access!

  private

  def authorize_setup_access!
    authorize! :manage, :setup
  end
end
