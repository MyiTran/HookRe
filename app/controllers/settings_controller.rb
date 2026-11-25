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

    updates = {}
    updates[:response_mode] = params[:response_mode] if params[:response_mode].present?
    updates[:status_code] = params[:status_code].to_i if params.key?(:status_code)
    updates[:delay_seconds] = params[:delay_seconds].to_i if params.key?(:delay_seconds)
    updates[:response_body] = params[:response_body].presence if params.key?(:response_body)

    if params[:steps].present?
      steps_data = if params[:steps].respond_to?(:values)
        params[:steps].values
      else
        Array(params[:steps])
      end
      setting.set_sequence_steps(steps_data)
      updates[:sequence_steps] = setting.sequence_steps
    elsif params[:sequence_steps].present?
      steps_data = begin
        JSON.parse(params[:sequence_steps])
      rescue JSON::ParserError
        []
      end
      setting.set_sequence_steps(steps_data)
      updates[:sequence_steps] = setting.sequence_steps
    end

    if setting.update(updates)
      flash[:notice] = "Updated #{setting.route_label} configuration."
    else
      flash[:alert] = "Could not update #{setting.route_label}: #{setting.errors.full_messages.join(', ')}"
    end

    redirect_to root_path(route: route_key)
  end

  def reset_sequence_progress
    route_key = ReceiverSetting.normalize_route_key(params[:route_key])
    setting = ReceiverSetting.for_route(route_key)
    setting.reset_sequence_progress!
    flash[:notice] = "Reset sequence progress to Step 1 for #{setting.route_label}."
    redirect_to root_path(route: route_key)
  end

  def reset_route_counter
    route_key = ReceiverSetting.normalize_route_key(params[:route_key])
    setting = ReceiverSetting.for_route(route_key)
    setting.reset_counter!
    flash[:notice] = "Reset counter for #{setting.route_label}."
    redirect_to root_path(route: route_key)
  end

  def update_receiver_secret
    route_key = params[:route_key].to_s
    return head :not_found unless SigningSecretStore.valid_route_key?(route_key)

    SigningSecretStore.set(route_key: route_key, value: params[:signing_secret])

    respond_to do |format|
      format.html do
        flash[:notice] = "Endpoint signing secret updated for #{route_key} receiver."
        redirect_to root_path(route: route_key)
      end
      format.json do
        render json: { configured: SigningSecretStore.configured_for?(route_key) }
      end
    end
  end

  def clear_receiver_secret
    route_key = params[:route_key].to_s
    return head :not_found unless SigningSecretStore.valid_route_key?(route_key)

    SigningSecretStore.clear(route_key: route_key)

    respond_to do |format|
      format.html do
        flash[:notice] = "Endpoint signing secret cleared for #{route_key} receiver."
        redirect_to root_path(route: route_key)
      end
      format.json do
        render json: { configured: false }
      end
    end
  end
end
