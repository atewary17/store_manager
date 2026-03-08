# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  # Organisations & Users
  resources :organisations, only: [:index, :show, :new, :create, :edit, :update] do
    resources :users, only: [:index, :show, :new, :create, :edit, :update]
    resources :product_categories, only: [:index, :create, :destroy],
      module: :organisations
  end

  # Setup / Master Data
  namespace :setup do
    resources :uoms
    resources :brands
    resources :product_categories
    resources :products do
      collection { get :export }
    end
    resources :shade_catalogues do
      collection { get :template; get :export; get :import, to: 'shade_catalogues#import_index'; get :import_new; post :import_create }
      member     { get :import_show; get :import_download_errors }
    end
    resources :product_imports, only: [:index, :new, :create, :show] do
      member     { get :download_errors }
      collection { get :template }
    end
    root 'uoms#index'
  end

  # Inventory
  namespace :inventory do
    resources :stock_levels, only: [:index]
    resource  :opening_stock, only: [:new, :create] do
      get :ledger, on: :collection
    end
  end

  # Purchasing
  namespace :purchasing do
    resources :suppliers do
      collection { get :search }
    end
    resources :purchase_invoices do
      member { post :confirm }
      collection { get :product_search }
    end
  end

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'
end