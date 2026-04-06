# app/controllers/organisations_controller.rb
class OrganisationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation, only: [:show, :edit, :update]

  # Only super_admin can list all orgs or create new ones
  before_action :require_super_admin!, only: [:index, :new, :create]

  # For edit/update: super_admin can edit any org; owner/admin can only edit their own
  before_action :require_edit_access!, only: [:edit, :update]

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
    if current_user.super_admin?
      @organisation = Organisation.find(params[:id])
    else
      # Scoped to own org only — prevents accessing other orgs by ID manipulation
      @organisation = Organisation.find(params[:id])
      unless @organisation.id == current_user.organisation_id
        redirect_to dashboard_path, alert: 'Access denied.' and return
      end
    end
  end

  def require_super_admin!
    redirect_to dashboard_path, alert: 'Access denied.' unless current_user.super_admin?
  end

  def require_edit_access!
    # super_admin: can edit any org
    # owner/admin: can only edit their own org
    # staff: cannot edit any org
    return if current_user.super_admin?
    return if (current_user.owner? || current_user.admin?) &&
              current_user.organisation_id == @organisation&.id
    redirect_to dashboard_path, alert: 'Access denied.'
  end

  def organisation_params
    params.require(:organisation).permit(
      :name,
      :gst_number,       # GSTIN — existing column, validated for uniqueness
      :state,            # Required for intra/inter-state GST determination
      :state_code,       # 2-digit GST state code
      :pan,              # PAN number
      :address,          # Registered business address
      :subscription_plan,
      :status
      # Note: :gstin column is synced from :gst_number via before_save callback
      # Do not permit :gstin separately — it would overwrite gst_number sync
    )
  end
end