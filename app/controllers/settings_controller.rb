class SettingsController < ApplicationController
  def update_response_mode
    mode = params[:response_mode].to_s
    if ReceiverSetting::VALID_MODES.include?(mode)
      ReceiverSetting.set_response_mode(mode)
      flash[:notice] = "Receiver response mode set to #{mode}."
    else
      flash[:alert] = "Invalid response mode: #{mode}."
    end

    redirect_to root_path
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
