class Sys::Admin::FrontController < Sys::Controller::Admin::Base
  def index
    @messages = Sys::Message.state_public.order(published_at: :desc)
    @maintenances = Sys::Maintenance.state_public.order(published_at: :desc)
  end
end
