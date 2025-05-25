Rails.application.routes.draw do
  root "application#serve_app"
  get "up" => "rails/health#show", as: :rails_health_check
end