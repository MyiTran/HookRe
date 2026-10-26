Rails.application.routes.draw do
  root "home#index"

  post "/send_event", to: "home#send_event", as: :send_event
  post "/response_mode", to: "settings#update_response_mode", as: :response_mode
  post "/receiver_settings", to: "settings#update_receiver_setting", as: :update_receiver_setting
  post "/signing_secret", to: "settings#update_signing_secret", as: :signing_secret
  delete "/signing_secret", to: "settings#clear_signing_secret", as: :clear_signing_secret

  post "/webhook", to: "webhooks#create", defaults: { route_slug: "default" }, as: :webhook
  post "/webhooks/:route_slug", to: "webhooks#create", as: :routed_webhook, constraints: { route_slug: /(success|failure|slow|custom)/ }
  delete "/webhooks/clear", to: "webhooks#clear_history", as: :clear_webhooks_history
  get "/webhooks/recent", to: "webhooks#recent", as: :recent_webhooks
  get "/webhooks/:id", to: "webhooks#show", as: :webhook_detail, constraints: { id: /\d+/ }

  get "up" => "rails/health#show", as: :rails_health_check
end
