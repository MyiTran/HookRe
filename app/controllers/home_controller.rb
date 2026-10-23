class HomeController < ApplicationController
  def index
    load_form_defaults
    load_receiver_data
  end

  def send_event
    hookyard_url = params[:hookyard_url].presence || "http://localhost:3000/api/v1/events"
    api_token = params[:api_token]
    event_type = params[:event_type].presence || "order.created"
    idempotency_key = params[:idempotency_key].presence || generate_idempotency_key
    payload = params[:payload].presence || default_payload

    result = EventSender.new(
      url: hookyard_url,
      token: api_token,
      event_type: event_type,
      idempotency_key: idempotency_key,
      payload_json: payload
    ).call

    flash[:event_result] = {
      "success" => result.success?,
      "status_code" => result.status_code,
      "body" => result.body,
      "error" => result.error
    }

    flash[:event_form] = {
      "hookyard_url" => hookyard_url,
      "event_type" => event_type,
      "idempotency_key" => idempotency_key,
      "payload" => payload
    }

    redirect_to root_path
  end

  private

  def load_form_defaults
    @api_token = ""

    if flash[:event_form].present?
      form_data = flash[:event_form]
      @hookyard_url = form_data["hookyard_url"]
      @event_type = form_data["event_type"]
      @idempotency_key = form_data["idempotency_key"]
      @payload = form_data["payload"]
    else
      @hookyard_url ||= "http://localhost:3000/api/v1/events"
      @event_type ||= "order.created"
      @idempotency_key ||= generate_idempotency_key
      @payload ||= default_payload
    end

    if flash[:event_result].present?
      res = flash[:event_result]
      @result = EventSender::Result.new(
        success: res["success"],
        status_code: res["status_code"],
        body: res["body"],
        error: res["error"]
      )
    end
  end

  def generate_idempotency_key
    "evt_#{Time.current.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4)}"
  end

  def default_payload
    JSON.pretty_generate({
      order_id: "ORD-001",
      amount: 120000
    })
  end

  def load_receiver_data
    @response_mode = ReceiverSetting.current_response_mode
    @webhooks = ReceivedWebhook.recent.limit(20)
    @webhook_count = ReceivedWebhook.count
  end
end
