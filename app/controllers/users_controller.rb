# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organisation
  before_action :authorize_access!
  before_action :set_user, only: [:show, :edit, :update]

  def index
    @users = @organisation.users.order(created_at: :desc)
  end

  def show; end

  def new
    @user = @organisation.users.build
  end

  def create
    @user = @organisation.users.build(user_params)
    # Generate a temporary password if none provided
    if params[:user][:password].blank?
      temp_password = SecureRandom.hex(8)
      @user.password = temp_password
      @user.password_confirmation = temp_password
      @temp_password = temp_password
    end

    if @user.save
      redirect_to organisation_user_path(@organisation, @user),
        notice: "User created successfully.#{@temp_password ? " Temporary password: #{@temp_password}" : ''}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if user_params[:password].blank?
      # Don't update password if field left empty
      result = @user.update(user_params.except(:password, :password_confirmation))
    else
      result = @user.update(user_params)
    end

    if result
      redirect_to organisation_user_path(@organisation, @user), notice: 'User updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_organisation
    @organisation = Organisation.find(params[:organisation_id])
  end

  def set_user
    @user = @organisation.users.find(params[:id])
  end

  def user_params
    params.require(:user).permit(
      :email, :role, :status,
      :password, :password_confirmation,
      :first_name, :last_name, :phone_number   
    )
  end

  def authorize_access!
    unless current_user.super_admin? || current_user.organisation_id == @organisation.id
      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
