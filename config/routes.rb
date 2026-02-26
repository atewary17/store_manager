# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  # Organisations & Users (tenant management)
  resources :organisations, only: [:index, :show, :new, :create, :edit, :update] do
    resources :users, only: [:index, :show, :new, :create, :edit, :update]
  end

  # Setup / Master Data (shared, platform-wide)
  namespace :setup do
    resources :uoms
    resources :product_categories
    resources :products

    root 'uoms#index'
  end

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'
end