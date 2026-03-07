# app/controllers/organisations/product_categories_controller.rb
class Organisations::ProductCategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize!
  before_action :set_organisation

  def index
    @assigned     = @organisation.product_categories.ordered
    @unassigned   = ProductCategory.active.ordered
                      .where.not(id: @assigned.select(:id))
  end

  def create
    category = ProductCategory.find(params[:product_category_id])
    @organisation.product_categories << category
    redirect_to organisation_product_categories_path(@organisation),
      notice: "#{category.name} added."
  rescue ActiveRecord::RecordInvalid
    redirect_to organisation_product_categories_path(@organisation),
      alert: "Category already assigned."
  end

  def destroy
    category = @organisation.product_categories.find(params[:id])
    @organisation.product_categories.delete(category)
    redirect_to organisation_product_categories_path(@organisation),
      notice: "#{category.name} removed."
  end

  private

  def set_organisation
    @organisation = Organisation.find(params[:organisation_id])
  end

  def authorize!
    unless current_user.super_admin? || current_user.owner?
      redirect_to dashboard_path, alert: 'Access denied.'
    end
  end
end
