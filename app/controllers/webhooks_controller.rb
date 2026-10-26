require "standardwebhooks"

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :clear_history]

  def create
    raw_body = request.raw_post.to_s
    route_key = params[:route_slug].presence || ReceiverSetting.normalize_route_key(request.path)
    setting = ReceiverSetting.for_route(route_key)

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

    # 1. Signature Verification
    parsed_body = nil
    verification_status = ReceivedWebhook::STATUS_NOT_VERIFIED
    verification_error = nil

    if SigningSecretStore.configured?
      verification_headers = {
        "webhook-id" => stored_headers["webhook-id"],
        "webhook-timestamp" => stored_headers["webhook-timestamp"],
        "webhook-signature" => stored_headers["webhook-signature"]
      }

      verified = false
      SigningSecretStore.secrets.each do |sec|
        begin
          wh = StandardWebhooks::Webhook.new(sec)
          parsed_body = wh.verify(raw_body, verification_headers)
          verified = true
          verification_error = nil
          break
        rescue StandardWebhooks::WebhookVerificationError => e
          verification_error ||= e.message
        end
      end

      if verified
        verification_status = ReceivedWebhook::STATUS_VERIFIED
      else
        verification_status = ReceivedWebhook::STATUS_REJECTED
      end
    elsif request.path == "/webhook"
      # Legacy endpoint without configured secret returns 503
      @received_webhook = ReceivedWebhook.create!(
        request_id: request_id,
        webhook_id: webhook_id,
        event_type: nil,
        headers: stored_headers,
        body: raw_body,
        received_at: Time.current,
        verification_status: ReceivedWebhook::STATUS_REJECTED,
        verification_error: "Endpoint signing secret is not configured in HookRe",
        response_status: 503,
        receiver_path: request.path,
        delay_seconds: 0
      )
      return render json: { error: "Endpoint signing secret is not configured" }, status: :service_unavailable
    else
      verification_status = ReceivedWebhook::STATUS_NOT_VERIFIED
      verification_error = "Endpoint signing secret is not configured in HookRe"
    end

    # 2. Determine event_type & fallback IDs
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

    # 3. Determine response status and delay
    if verification_status == ReceivedWebhook::STATUS_REJECTED
      response_status = 401
      delay_seconds = 0
    else
      response_status = setting.status_code
      delay_seconds = setting.delay_seconds.to_i
    end

    # 4. Store received webhook
    @received_webhook = ReceivedWebhook.create!(
      request_id: request_id,
      webhook_id: webhook_id,
      event_type: event_type,
      headers: stored_headers,
      body: raw_body,
      received_at: Time.current,
      verification_status: verification_status,
      verification_error: verification_error,
      response_status: response_status,
      receiver_path: request.path,
      delay_seconds: delay_seconds
    )

    # 5. Delay before returning response if configured
    if delay_seconds > 0
      sleep(delay_seconds)
    end

    # 6. Rejected requests always return 401
    if verification_status == ReceivedWebhook::STATUS_REJECTED
      return render json: {
        error: "Webhook signature verification failed",
        detail: verification_error
      }, status: :unauthorized
    end

    # 7. Return configured response
    if response_status == 204
      head :no_content
    elsif setting.response_body.present?
      body = setting.response_body
      is_json = body.strip.start_with?("{", "[") rescue false
      render plain: body, status: response_status, content_type: (is_json ? "application/json" : "text/plain")
    elsif setting.response_mode == "large"
      render json: {
        received: true,
        webhook_id: @received_webhook.id,
        padding: "X" * 5000
      }, status: :ok
    elsif response_status >= 500
      render json: {
        error: Rack::Utils::HTTP_STATUS_CODES[response_status] || "Internal server error",
        webhook_id: @received_webhook.id
      }, status: response_status
    elsif response_status >= 400
      render json: {
        error: Rack::Utils::HTTP_STATUS_CODES[response_status] || "Client error",
        webhook_id: @received_webhook.id
      }, status: response_status
    else
      render json: { received: true, webhook_id: @received_webhook.id }, status: response_status
    end
  end

  def show
    @webhook = ReceivedWebhook.find(params[:id])
  end

  def recent
    @active_route = params[:route].presence || "all"
    @webhooks = ReceivedWebhook.recent.for_route(@active_route).limit(100)
    @webhook_count = ReceivedWebhook.for_route(@active_route).count

    respond_to do |format|
      format.html { render partial: "webhooks/recent_list", locals: { webhooks: @webhooks, webhook_count: @webhook_count, active_route: @active_route } }
      format.json { render json: { count: @webhook_count, webhooks: @webhooks } }
    end
  end

  def clear_history
    route_filter = params[:route].presence
    if route_filter.present? && route_filter != "all"
      ReceivedWebhook.for_route(route_filter).delete_all
      flash[:notice] = "Cleared received requests for #{route_filter} receiver."
    else
      ReceivedWebhook.delete_all
      flash[:notice] = "Cleared all received requests history."
    end
    redirect_to root_path(route: route_filter)
  end
end
