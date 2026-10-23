Rails.application.routes.draw do
  root "home#index"

  post "/send_event", to: "home#send_event", as: :send_event
  post "/response_mode", to: "settings#update_response_mode", as: :response_mode
  post "/signing_secret", to: "settings#update_signing_secret", as: :signing_secret
  delete "/signing_secret", to: "settings#clear_signing_secret", as: :clear_signing_secret

  post "/webhook", to: "webhooks#create", as: :webhook
  get "/webhooks/recent", to: "webhooks#recent", as: :recent_webhooks
  get "/webhooks/:id", to: "webhooks#show", as: :webhook_detail

  get "up" => "rails/health#show", as: :rails_health_check
end
