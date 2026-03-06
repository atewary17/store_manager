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
    resources :brands
    resources :product_categories
    resources :products do
      collection { get :export }
    end
    resources :shade_catalogues do
      collection do
        get :template
        get :export
        get  :import,        action: :import_index
        get  :import_new,    action: :import_new
        post :import_create, action: :import_create
      end
      member do
        get 'import_show',           action: :import_show,           as: :shade_catalogue_import_show
        get 'import_download_errors', action: :import_download_errors, as: :shade_catalogue_import_download_errors
      end
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