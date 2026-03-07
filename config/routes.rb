# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  # Organisations & Users (tenant management)
  resources :organisations, only: [:index, :show, :new, :create, :edit, :update] do
    resources :users, only: [:index, :show, :new, :create, :edit, :update]
    resources :product_categories, only: [:index, :create, :destroy],
      module: :organisations
  end

  # Setup / Master Data (shared, platform-wide)
  namespace :setup do
    resources :uoms
    resources :product_categories
    resources :products do
      collection { get :export }
    end
    resources :product_imports, only: [:index, :new, :create, :show] do
      member do
        get :download_errors
      end
      collection do
        get :template
      end
    end

    root 'uoms#index'
  end

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'
end