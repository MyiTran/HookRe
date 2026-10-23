require "standardwebhooks"

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    raw_body = request.raw_post.to_s

    # Capture useful headers
    stored_headers = {}
    stored_headers["webhook-id"] = request.headers["Webhook-Id"] || request.headers["HTTP_WEBHOOK_ID"]
    stored_headers["webhook-request-id"] = request.headers["Webhook-Request-Id"] || request.headers["HTTP_WEBHOOK_REQUEST_ID"] || request.headers["X-Request-Id"]
    stored_headers["webhook-timestamp"] = request.headers["Webhook-Timestamp"] || request.headers["HTTP_WEBHOOK_TIMESTAMP"]
    stored_headers["webhook-signature"] = request.headers["Webhook-Signature"] || request.headers["HTTP_WEBHOOK_SIGNATURE"]
    stored_headers["content-type"] = request.content_type || request.headers["Content-Type"]
    stored_headers["user-agent"] = request.user_agent || request.headers["User-Agent"]

    # Also capture any custom webhook headers
    request.headers.each do |key, value|
      next unless value.is_a?(String)
      norm_key = key.sub(/^HTTP_/, "").tr("_", "-").downcase
      if norm_key.start_with?("webhook-") || norm_key.start_with?("x-webhook-")
        stored_headers[norm_key] ||= value
      end
    end

    stored_headers.compact!

    webhook_id = stored_headers["webhook-id"]
    request_id = stored_headers["webhook-request-id"] || request.request_id

    # 1. Check if signing secret is configured
    unless SigningSecretStore.configured?
      @received_webhook = ReceivedWebhook.create!(
        request_id: request_id,
        webhook_id: webhook_id,
        event_type: nil,
        headers: stored_headers,
        body: raw_body,
        received_at: Time.current,
        verification_status: ReceivedWebhook::STATUS_REJECTED,
        verification_error: "Endpoint signing secret is not configured in HookRe",
        response_status: 503
      )
      return render json: { error: "Endpoint signing secret is not configured" }, status: :service_unavailable
    end

    # 2. Verify signature with standardwebhooks
    verification_headers = {
      "webhook-id" => stored_headers["webhook-id"],
      "webhook-timestamp" => stored_headers["webhook-timestamp"],
      "webhook-signature" => stored_headers["webhook-signature"]
    }

    parsed_body = nil
    verification_status = ReceivedWebhook::STATUS_REJECTED
    verification_error = nil

    begin
      wh = StandardWebhooks::Webhook.new(SigningSecretStore.secret)
      parsed_body = wh.verify(raw_body, verification_headers)
      verification_status = ReceivedWebhook::STATUS_VERIFIED
    rescue StandardWebhooks::WebhookVerificationError => e
      verification_status = ReceivedWebhook::STATUS_REJECTED
      verification_error = e.message
    end

    # 3. Determine event_type & fallback IDs
    event_type = request.headers["Webhook-Event"] || request.headers["HTTP_WEBHOOK_EVENT"]
    if parsed_body.is_a?(Hash)
      event_type ||= parsed_body["type"] || parsed_body["event_type"] || parsed_body["event"]
      webhook_id ||= parsed_body["id"] || parsed_body["webhook_id"]
    elsif raw_body.present?
      begin
        fallback_json = JSON.parse(raw_body)
        if fallback_json.is_a?(Hash)
          event_type ||= fallback_json["type"] || fallback_json["event_type"] || fallback_json["event"]
          webhook_id ||= fallback_json["id"] || fallback_json["webhook_id"]
        end
      rescue JSON::ParserError
        # Non-JSON payload
      end
    end

    # 4. Determine response status and response mode
    response_mode = ReceiverSetting.current_response_mode
    if verification_status == ReceivedWebhook::STATUS_REJECTED
      response_status = 401
    else
      response_status = case response_mode
                        when "204" then 204
                        when "500" then 500
                        when "503" then 503
                        when "large", "200" then 200
                        else 200
                        end
    end

    # 5. Store received webhook with recorded response status
    @received_webhook = ReceivedWebhook.create!(
      request_id: request_id,
      webhook_id: webhook_id,
      event_type: event_type,
      headers: stored_headers,
      body: raw_body,
      received_at: Time.current,
      verification_status: verification_status,
      verification_error: verification_error,
      response_status: response_status
    )

    # 6. Rejected requests always return 401
    if verification_status == ReceivedWebhook::STATUS_REJECTED
      return render json: {
        error: "Webhook signature verification failed",
        detail: verification_error
      }, status: :unauthorized
    end

    # 7. Verified requests apply the selected response mode
    case response_mode
    when "204"
      head :no_content
    when "500"
      render json: { error: "Simulated internal server error", webhook_id: @received_webhook.id }, status: :internal_server_error
    when "503"
      render json: { error: "Simulated service unavailable", webhook_id: @received_webhook.id }, status: :service_unavailable
    when "large"
      render json: {
        received: true,
        webhook_id: @received_webhook.id,
        padding: "X" * 5000
      }, status: :ok
    else
      render json: { received: true }, status: :ok
    end
  end

  def show
    @webhook = ReceivedWebhook.find(params[:id])
  end

  def recent
    @webhooks = ReceivedWebhook.recent.limit(20)
    @webhook_count = ReceivedWebhook.count

    respond_to do |format|
      format.html { render partial: "webhooks/recent_list", locals: { webhooks: @webhooks, webhook_count: @webhook_count } }
      format.json { render json: { count: @webhook_count, webhooks: @webhooks } }
    end
  end
end
