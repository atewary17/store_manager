# app/controllers/organisations_controller.rb
class OrganisationsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_super_admin!, except: [:show]
  before_action :set_organisation, only: [:show, :edit, :update]

  def index
    @organisations = Organisation.includes(:users).all.order(created_at: :desc)
  end

  def show
    @users = @organisation.users.order(created_at: :desc)
  end

  def new
    @organisation = Organisation.new
  end

  def create
    @organisation = Organisation.new(organisation_params)
    if @organisation.save
      redirect_to organisation_path(@organisation), notice: 'Organisation created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @organisation.update(organisation_params)
      redirect_to organisation_path(@organisation), notice: 'Organisation updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_organisation
    @organisation = Organisation.find(params[:id])
  end

  def organisation_params
    params.require(:organisation).permit(:name, :gst_number, :address, :subscription_plan, :status)
  end

  def authorize_super_admin!
    redirect_to root_path, alert: 'Access denied.' unless current_user.super_admin?
  end
end
