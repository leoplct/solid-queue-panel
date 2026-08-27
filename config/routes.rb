# frozen_string_literal: true

SolidQueuePanel::Engine.routes.draw do
  root to: "dashboard#index"

  resources :jobs, only: %i[index show destroy] do
    member do
      post :retry
      post :dispatch_now
    end

    collection do
      post :bulk
      get :duplicates
      post :remove_duplicates
    end
  end

  resources :queues, only: %i[index show], param: :name, constraints: { name: %r{[^/]+} } do
    member do
      post :pause
      post :resume
      delete :clear
    end
  end

  resources :processes, only: %i[index show] do
    collection do
      post :prune
    end
  end

  resources :recurring_tasks, only: %i[index show], param: :key, constraints: { key: %r{[^/]+} }

  resource :metrics, only: :show
  resource :resources, only: :show
  resource :settings, only: :show do
    get :report
  end
  resource :theme, only: :update

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get "assets/:digest/:file", to: "assets#show", as: :panel_asset, format: false,
      constraints: { digest: /[\w.-]+/, file: /[\w.-]+/ }
end
