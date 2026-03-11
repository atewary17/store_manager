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
      collection { get :template; get :export }
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

  # Customers (shared — used by Sales, CRM, etc.)
  resources :customers do
    collection { get :search }
  end

  # Sales
  namespace :sales do
    resources :sales_invoices do
      member     { post :confirm; get :preview; post :void; post :mark_as_paid }
      collection { get :product_search; get :shade_search; get :base_search }
      resources :sale_payments, only: [:create, :show, :destroy]
    end
    resources :creditors, only: [:index, :show]
  end

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'
end