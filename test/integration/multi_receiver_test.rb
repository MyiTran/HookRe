require "test_helper"
require "standardwebhooks"

class MultiReceiverTest < ActionDispatch::IntegrationTest
  TEST_SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"

  setup do
    SigningSecretStore.reset_to_default!
    %w[success failure slow custom].each do |route|
      SigningSecretStore.set(route_key: route, value: TEST_SECRET)
    end
    ReceivedWebhook.delete_all
  end

  teardown do
    SigningSecretStore.reset_to_default!
  end

  def sign_payload(secret, msg_id, timestamp, payload)
    wh = StandardWebhooks::Webhook.new(secret)
    wh.sign(msg_id, timestamp.to_i.to_s, payload)
  end

  test "success receiver responds with 200 OK by default and records path" do
    msg_id = "msg_success_001"
    timestamp = Time.now.to_i.to_s
    payload = '{"event":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post "/webhooks/success",
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal true, json["received"]

    webhook = ReceivedWebhook.last
    assert_equal "/webhooks/success", webhook.receiver_path
    assert_equal 200, webhook.response_status
    assert_equal "Verified", webhook.signature_status_text
    assert_equal 0, webhook.delay_seconds
  end

  test "failure receiver responds with 500 Internal Server Error by default and records path" do
    msg_id = "msg_failure_001"
    timestamp = Time.now.to_i.to_s
    payload = '{"event":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post "/webhooks/failure",
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :internal_server_error
    json = JSON.parse(response.body)
    assert_equal "Internal Server Error", json["error"]

    webhook = ReceivedWebhook.last
    assert_equal "/webhooks/failure", webhook.receiver_path
    assert_equal 500, webhook.response_status
    assert_equal "Verified", webhook.signature_status_text
  end

  test "slow receiver executes configured delay and records path" do
    slow_setting = ReceiverSetting.for_route("slow")
    slow_setting.update!(delay_seconds: 1) # Use 1 second in test to keep it fast

    msg_id = "msg_slow_001"
    timestamp = Time.now.to_i.to_s
    payload = '{"event":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    post "/webhooks/slow",
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    assert_response :ok
    assert elapsed >= 0.9, "Expected request to be delayed by ~1 second, took #{elapsed}s"

    webhook = ReceivedWebhook.last
    assert_equal "/webhooks/slow", webhook.receiver_path
    assert_equal 200, webhook.response_status
    assert_equal 1, webhook.delay_seconds
    assert webhook.delayed?
  end

  test "custom receiver responds with configured custom status and body" do
    custom_setting = ReceiverSetting.for_route("custom")
    custom_setting.update!(status_code: 429, response_body: '{"error":"Too Many Requests"}')

    msg_id = "msg_custom_001"
    timestamp = Time.now.to_i.to_s
    payload = '{"event":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post "/webhooks/custom",
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :too_many_requests
    assert_equal '{"error":"Too Many Requests"}', response.body

    webhook = ReceivedWebhook.last
    assert_equal "/webhooks/custom", webhook.receiver_path
    assert_equal 429, webhook.response_status
    assert_equal "Responded 429 Too Many Requests", webhook.response_status_text
  end

  test "requests received at one path never change configuration or history of another path" do
    ReceiverSetting.for_route("success").update!(status_code: 200)
    ReceiverSetting.for_route("failure").update!(status_code: 500)

    # Receive request at success
    ts = Time.now.to_i.to_s
    post "/webhooks/success",
      params: '{"e":"1"}',
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => "msg_ind_1",
        "HTTP_WEBHOOK_TIMESTAMP" => ts,
        "HTTP_WEBHOOK_SIGNATURE" => sign_payload(TEST_SECRET, "msg_ind_1", ts, '{"e":"1"}')
      }
    assert_response :ok

    # Receive request at failure
    post "/webhooks/failure",
      params: '{"e":"2"}',
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => "msg_ind_2",
        "HTTP_WEBHOOK_TIMESTAMP" => ts,
        "HTTP_WEBHOOK_SIGNATURE" => sign_payload(TEST_SECRET, "msg_ind_2", ts, '{"e":"2"}')
      }
    assert_response :internal_server_error

    # Ensure configs remain independent
    assert_equal 200, ReceiverSetting.for_route("success").status_code
    assert_equal 500, ReceiverSetting.for_route("failure").status_code

    # Ensure histories remain independent
    assert_equal 1, ReceivedWebhook.for_route("success").count
    assert_equal 1, ReceivedWebhook.for_route("failure").count
    assert_equal 2, ReceivedWebhook.for_route("all").count
  end

  test "unconfigured signing secret on multi-receiver route fails closed" do
    SigningSecretStore.clear(route_key: "success")

    post "/webhooks/success",
      params: '{"event":"unverified.test"}',
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => "msg_no_secret",
        "HTTP_WEBHOOK_TIMESTAMP" => Time.now.to_i.to_s
      }

    assert_response :service_unavailable
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_equal 503, webhook.response_status
  end

  test "invalid signature on multi-receiver route returns 401 and is marked Invalid signature" do
    post "/webhooks/success",
      params: '{"event":"tampered"}',
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => "msg_invalid_sig",
        "HTTP_WEBHOOK_TIMESTAMP" => Time.now.to_i.to_s,
        "HTTP_WEBHOOK_SIGNATURE" => "v1,wrong_sig"
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_equal "Invalid signature", webhook.signature_status_text
    assert_equal "badge-sig-invalid", webhook.signature_status_badge_class
    assert_equal 401, webhook.response_status
  end

  test "filtering recent webhooks by route returns only requests for that route" do
    ReceivedWebhook.create!(receiver_path: "/webhooks/success", webhook_id: "wh_s", response_status: 200, received_at: Time.current)
    ReceivedWebhook.create!(receiver_path: "/webhooks/failure", webhook_id: "wh_f", response_status: 500, received_at: Time.current + 1.second)

    get recent_webhooks_path(route: "success")
    assert_response :success
    assert_includes response.body, "wh_s"
    assert_not_includes response.body, "wh_f"

    get recent_webhooks_path(route: "failure")
    assert_response :success
    assert_includes response.body, "wh_f"
    assert_not_includes response.body, "wh_s"

    get recent_webhooks_path(route: "all")
    assert_response :success
    assert_includes response.body, "wh_s"
    assert_includes response.body, "wh_f"
  end

  test "POST /receiver_settings updates route configuration with validation" do
    post update_receiver_setting_path, params: {
      route_key: "custom",
      status_code: 408,
      delay_seconds: 15,
      response_body: "Request timed out by HookRe"
    }
    assert_redirected_to root_path(route: "custom")
    follow_redirect!

    setting = ReceiverSetting.for_route("custom")
    assert_equal 408, setting.status_code
    assert_equal 15, setting.delay_seconds
    assert_equal "Request timed out by HookRe", setting.response_body
    assert_equal "Responding 408 Request Timeout", setting.active_status_text
    assert_equal "Responds after 15 seconds", setting.delay_label
  end

  test "POST /receiver_settings rejects invalid inputs" do
    post update_receiver_setting_path, params: {
      route_key: "custom",
      status_code: 999,
      delay_seconds: 100
    }
    assert_redirected_to root_path(route: "custom")
    follow_redirect!

    assert_select ".flash-alert", text: /Could not update/
    setting = ReceiverSetting.for_route("custom")
    assert_not_equal 999, setting.status_code
  end

  test "DELETE /webhooks/clear deletes received request history" do
    ReceivedWebhook.create!(receiver_path: "/webhooks/success", webhook_id: "wh_to_delete", response_status: 200, received_at: Time.current)
    assert_equal 1, ReceivedWebhook.count

    delete clear_webhooks_history_path
    assert_redirected_to root_path
    follow_redirect!

    assert_equal 0, ReceivedWebhook.count
    assert_select ".flash-notice", text: /Cleared all received requests history/
  end
end
