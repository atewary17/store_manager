# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  layout false

  def home
    redirect_to dashboard_path if user_signed_in?
  end
end
