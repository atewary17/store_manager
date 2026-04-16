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
  # Accounting — using scope so inner `as:` names get the accounting_ prefix correctly
  # scope(as: :accounting) prepends "accounting_" to each route's `as:` name.
  # URL prefix /accounting, controllers in Accounting:: module.
  scope '/accounting', module: :accounting, as: :accounting do
    get  'gst',              to: 'gst_reports#index',        as: :gst_reports
    get  'gst/gstr1',        to: 'gst_reports#gstr1',        as: :gstr1
    get  'gst/gstr3b',       to: 'gst_reports#gstr3b',       as: :gstr3b
    get  'gst/itc',          to: 'gst_reports#itc',          as: :gst_itc
    get  'gst/hsn',          to: 'gst_reports#hsn',          as: :gst_hsn
    post 'gst/close_period', to: 'gst_reports#close_period', as: :gst_close_period
  end

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
    resources :referrers do
      collection { get :search }
    end

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

  # ── Reports ──────────────────────────────────────────────────────────────
  namespace :reports do
    resources :sales, only: [:index] do
      collection do
        get :export   # → export_reports_sales_path
      end
    end
    resources :purchases, only: [:index] do
      collection do
        get :export   # → export_reports_purchases_path
      end
    end
  end

  get  'dashboard', to: 'dashboard#index', as: :dashboard
  root 'dashboard#index'

  # ── Mobile API — v1 ──────────────────────────────────────────────────────
  # All endpoints under /api/v1/
  # Authentication: POST /api/v1/auth/login → returns JWT Bearer token
  # All other endpoints require:  Authorization: Bearer <token>
  namespace :api do
    namespace :v1 do

      # Auth
      post 'auth/login',  to: 'auth#login'
      post 'auth/logout', to: 'auth#logout'
      get  'auth/me',     to: 'auth#me'

      # Purchase Invoices
      resources :purchase_invoices, only: [:index, :show, :create] do
        member     { post :confirm }
        collection { post :from_digitiser }
      end

      # Sales Invoices
      resources :sales_invoices, only: [:index, :show, :create] do
        member { post :confirm; post :void }
      end

      # Accounts & Payments
      get 'accounts/payable',    to: 'accounts#payable'
      get 'accounts/receivable', to: 'accounts#receivable'
      get 'accounts/payments',   to: 'accounts#payments'

    end
  end

end