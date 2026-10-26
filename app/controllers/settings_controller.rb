class SettingsController < ApplicationController
  skip_before_action :verify_authenticity_token
  def update_response_mode
    mode = params[:response_mode].to_s
    route_key = params[:route_key].presence || "default"
    if ReceiverSetting::VALID_MODES.include?(mode)
      ReceiverSetting.set_response_mode(mode, route_key)
      flash[:notice] = "Receiver response mode set to #{mode}."
    else
      flash[:alert] = "Invalid response mode: #{mode}."
    end

    redirect_to root_path
  end

  def update_receiver_setting
    route_key = ReceiverSetting.normalize_route_key(params[:route_key])
    setting = ReceiverSetting.for_route(route_key)

    status_code = (params[:status_code].presence || setting.status_code).to_i
    delay_seconds = (params[:delay_seconds].presence || setting.delay_seconds).to_i
    # Allow explicitly clearing delay if passed as 0 or empty string
    delay_seconds = params[:delay_seconds].to_i if params.key?(:delay_seconds)
    response_body = params.key?(:response_body) ? params[:response_body].presence : setting.response_body

    if setting.update(status_code: status_code, delay_seconds: delay_seconds, response_body: response_body)
      flash[:notice] = "Updated #{setting.route_label} configuration."
    else
      flash[:alert] = "Could not update #{setting.route_label}: #{setting.errors.full_messages.join(', ')}"
    end

    redirect_to root_path(route: route_key)
  end

  def update_signing_secret
    secret = params[:signing_secret].to_s.strip
    if secret.present?
      SigningSecretStore.set(secret)
      flash[:notice] = "Endpoint signing secret configured."
    else
      SigningSecretStore.clear
      flash[:notice] = "Endpoint signing secret cleared."
    end

    redirect_to root_path
  end

  def clear_signing_secret
    SigningSecretStore.clear
    flash[:notice] = "Endpoint signing secret cleared."
    redirect_to root_path
  end
end
