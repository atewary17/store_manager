# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation, except: [:profile, :update_profile]
  before_action :authorize_access!, except: [:profile, :update_profile]
  before_action :set_user, only: [:show, :edit, :update]

  # GET /profile — any logged-in user can view/edit their own profile
  def profile
    @user = current_user
  end

  # PATCH /profile — save profile + preferences
  def update_profile
    @user = current_user
    prefs = params[:preferences] || {}

    # Only super_admin can change the global AI provider
    # Any user can set their own preferred provider (used as override when present)
    pref_update = {
      'ai_provider'  => prefs[:ai_provider].to_s.presence,
      'theme'        => prefs[:theme].to_s.presence,
    }.compact

    user_attrs = profile_params

    success = if user_attrs[:password].blank?
      @user.update(user_attrs.except(:password, :password_confirmation)
                              .merge(preferences: @user.preferences.merge(pref_update)))
    else
      @user.update(user_attrs.merge(preferences: @user.preferences.merge(pref_update)))
    end

    if success
      redirect_to profile_path, notice: 'Profile updated.'
    else
      render :profile, status: :unprocessable_entity
    end
  end

  def index
    @users = @organisation.users.order(created_at: :desc)
  end

  def show; end

  def new
    @user = @organisation.users.build
  end

  def create
    @user = @organisation.users.build(user_params)

    if params[:user][:password].blank?
      temp_password = SecureRandom.hex(8)
      @user.password              = temp_password
      @user.password_confirmation = temp_password
      @temp_password              = temp_password
    end

    if @user.save
      redirect_to organisation_user_path(@organisation, @user),
        notice: "User created.#{@temp_password ? " Temporary password: #{@temp_password}" : ''}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    result = if user_params[:password].blank?
      @user.update(user_params.except(:password, :password_confirmation))
    else
      @user.update(user_params)
    end

    if result
      redirect_to organisation_user_path(@organisation, @user), notice: 'User updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_organisation
    if current_user.super_admin?
      @organisation = Organisation.find(params[:organisation_id])
    else
      # Non-super-admins are always scoped to their own org
      @organisation = current_user.organisation
      # Prevent URL manipulation to another org's users
      unless @organisation&.id.to_s == params[:organisation_id].to_s
        redirect_to dashboard_path, alert: 'Access denied.' and return
      end
    end
  end

  def set_user
    @user = @organisation.users.find(params[:id])
  end

  def authorize_access!
    # super_admin: access any org's users
    # owner/admin: only their own org's users
    # staff: only read (show/index), no create/edit
    return if current_user.super_admin?
    return if current_user.organisation_id == @organisation&.id &&
              (current_user.owner? || current_user.admin?)

    # Staff can only view, not manage
    if current_user.staff? && action_name.in?(%w[show index])
      return if current_user.organisation_id == @organisation&.id
    end

    redirect_to dashboard_path, alert: 'Access denied.'
  end

  def user_params
    params.require(:user).permit(
      :first_name, :last_name, :phone_number,
      :email, :role, :status,
      :password, :password_confirmation
    )
  end

  def profile_params
    params.require(:user).permit(
      :first_name, :last_name, :phone_number,
      :password, :password_confirmation
    )
  end
end