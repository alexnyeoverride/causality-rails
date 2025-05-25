class ApplicationController < ActionController::Base
  def serve_app
    render 'layouts/application', layout: false
  end
end