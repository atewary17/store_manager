# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  # User profile — any logged-in user
  get   '/profile', to: 'users#profile',       as: :profile
  patch '/profile', to: 'users#update_profile', as: :update_profile
  put   '/profile', to: 'users#update_profile'

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
      collection do
        get  :export
        get  :product_register
        get  :product_register_export
        post :approve_pending,  path: ':id/approve'
        delete :reject_pending, path: ':id/reject_pending'
      end
    end
    resources :shade_catalogues do
      collection do
        get  :template
        get  :export
        get  'import',     action: :import_index, as: :import
        get  'import/new', action: :import_new,   as: :import_new
        post 'import',     action: :import_create
      end
    end

    resources :product_imports, only: [:index, :new, :create, :show] do
      member     { get :download_errors }
      collection { get :template }
    end
    root 'uoms#index'
  end

  # Inventory
  namespace :inventory do
    get  'tinting_machine',                        to: 'tinting_machine#index',      as: :tinting_machine
    get  'tinting_machine/:brand_id',              to: 'tinting_machine#show',       as: :tinting_machine_brand
    post 'tinting_machine/:brand_id/load',         to: 'tinting_machine#load_canister',   as: :tinting_machine_load
    patch 'tinting_machine/:brand_id/adjust/:id',  to: 'tinting_machine#adjust',          as: :tinting_machine_adjust
    delete 'tinting_machine/:brand_id/remove/:id',       to: 'tinting_machine#remove_canister', as: :tinting_machine_remove
    post   'tinting_machine/:brand_id/reload_last/:slot_number', to: 'tinting_machine#reload_last',      as: :tinting_machine_reload_last
    resources :stock_levels, only: [:index] do
      member { post :quick_adjust }
      collection { get :export }
    end
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
      resources :supplier_payments, only: [:create, :destroy],
                                    controller: 'supplier_payments'
    end
    # Product enrichment endpoints
    post 'enrich_product',       to: 'enrich#enrich_product'
    post 'save_enriched_product', to: 'enrich#save_enriched_product'
    # Accounting — Purchasing side
    resources :accounts_payable, only: [:index, :show],
                                  controller: 'accounts_payable'
    resources :supplier_payments, only: [:index], controller: 'supplier_payments'
    get 'supplier_payments/:id', to: 'supplier_payments#payment_show',
                                 as: :supplier_payment
    resources :digitise, only: [:index, :new, :create, :show] do
      member do
        post :confirm
        post :retry
        post :stop
        get  :raw_response
      end
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
    # Accounting — Sales side
    resources :accounts_receivable, only: [:index, :show],
                                    controller: 'accounts_receivable'
    resources :customer_receipts, only: [:index], controller: 'sale_payments'
    get 'customer_receipts/:id', to: 'sale_payments#payment_show',
                                 as: :customer_receipt
  end

  # Shade import detail routes — outside namespace to control helper names precisely
  get  '/setup/shade_catalogues/imports/:id',
       to:  'setup/shade_catalogues#import_show',
       as:  'import_show_setup_shade_catalogue'
  get  '/setup/shade_catalogues/imports/:id/download_errors',
       to:  'setup/shade_catalogues#import_download_errors',
       as:  'import_download_errors_setup_shade_catalogue'

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'
end