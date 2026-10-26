require "test_helper"
require "standardwebhooks"

class WebhookReceiverTest < ActionDispatch::IntegrationTest
  TEST_SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
  SECOND_SECRET = "whsec_V29uZGVyZnVsU2VjcmV0Rm9yVGVzdGluZw=="

  setup do
    SigningSecretStore.reset_to_default!
    SigningSecretStore.set(TEST_SECRET)
    ReceiverSetting.set_response_mode("200")
  end

  teardown do
    SigningSecretStore.reset_to_default!
  end

  def sign_payload(secret, msg_id, timestamp, payload)
    wh = StandardWebhooks::Webhook.new(secret)
    wh.sign(msg_id, timestamp.to_i.to_s, payload)
  end

  # --- Signing verification tests ---

  test "correct secret, body, timestamp, and headers returns configured success response" do
    msg_id = "msg_delivery_001"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_1","type":"order.created","data":{"amount":120000}}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    assert_difference("ReceivedWebhook.count", 1) do
      post webhook_path,
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_WEBHOOK_ID" => msg_id,
          "HTTP_WEBHOOK_REQUEST_ID" => "req_deliv_001",
          "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
          "HTTP_WEBHOOK_SIGNATURE" => sig,
          "HTTP_USER_AGENT" => "HookYard/1.0"
        }
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal true, json["received"]

    webhook = ReceivedWebhook.last
    assert_equal "verified", webhook.verification_status
    assert_nil webhook.verification_error
    assert_equal "order.created", webhook.event_type
    assert_equal msg_id, webhook.webhook_id
    assert_equal "req_deliv_001", webhook.request_id
    assert_equal payload, webhook.body
    assert_equal "application/json", webhook.headers["content-type"]
    assert_equal "HookYard/1.0", webhook.headers["user-agent"]
    assert_equal sig, webhook.headers["webhook-signature"]
  end

  test "wrong signing secret returns 401 and is marked rejected" do
    msg_id = "msg_wrong_secret"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_2","type":"order.created"}'
    # Sign with SECOND_SECRET, but HookRe is configured with TEST_SECRET
    sig = sign_payload(SECOND_SECRET, msg_id, timestamp, payload)

    assert_difference("ReceivedWebhook.count", 1) do
      post webhook_path,
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_WEBHOOK_ID" => msg_id,
          "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
          "HTTP_WEBHOOK_SIGNATURE" => sig
        }
    end

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "Webhook signature verification failed", json["error"]

    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "No matching signature found"
  end

  test "modified raw body returns 401" do
    msg_id = "msg_tampered"
    timestamp = Time.now.to_i.to_s
    original_payload = '{"id":"evt_orig","type":"order.created"}'
    tampered_payload = '{"id":"evt_tampered","type":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, original_payload)

    post webhook_path,
      params: tampered_payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
  end

  test "missing webhook-id returns 401" do
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_3","type":"order.created"}'
    sig = sign_payload(TEST_SECRET, "dummy", timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "Missing required headers"
  end

  test "missing webhook-timestamp returns 401" do
    msg_id = "msg_no_time"
    payload = '{"id":"evt_4","type":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, Time.now.to_i.to_s, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "Missing required headers"
  end

  test "missing webhook-signature returns 401" do
    msg_id = "msg_no_sig"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_5","type":"order.created"}'

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "Missing required headers"
  end

  test "expired timestamp returns 401" do
    msg_id = "msg_expired"
    expired_timestamp = (Time.now - 10.minutes).to_i.to_s
    payload = '{"id":"evt_6","type":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, expired_timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => expired_timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :unauthorized
    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "Message timestamp too old"
  end

  test "missing receiver signing-secret configuration returns 503" do
    SigningSecretStore.clear

    post webhook_path,
      params: '{"id":"evt_7"}',
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => "msg_no_conf",
        "HTTP_WEBHOOK_TIMESTAMP" => Time.now.to_i.to_s,
        "HTTP_WEBHOOK_SIGNATURE" => "v1,dummy"
      }

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_includes json["error"], "Endpoint signing secret is not configured"

    webhook = ReceivedWebhook.last
    assert_equal "rejected", webhook.verification_status
    assert_includes webhook.verification_error, "not configured"
  end

  test "replacing configured secret makes signatures using previous secret fail immediately and new secret succeeds" do
    msg_id = "msg_rot_1"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_rot","type":"invoice.paid"}'

    old_sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)
    new_sig = sign_payload(SECOND_SECRET, msg_id, timestamp, payload)

    # Replace secret with SECOND_SECRET
    SigningSecretStore.set(SECOND_SECRET)

    # 1. Delivery with old secret must now FAIL with 401
    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => old_sig
      }
    assert_response :unauthorized
    assert_equal "rejected", ReceivedWebhook.last.verification_status

    # 2. Delivery with new secret must SUCCEED with 200
    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => new_sig
      }
    assert_response :ok
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "raw secret never appears in rendered HTML, JSON responses, or ReceivedWebhook attributes" do
    msg_id = "msg_leak_check"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_leak","type":"order.created"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }
    assert_response :ok
    assert_no_match(/#{Regexp.escape(TEST_SECRET)}/, response.body)

    webhook = ReceivedWebhook.last
    # Check all database attributes
    webhook.attributes.each do |key, val|
      assert_no_match(/#{Regexp.escape(TEST_SECRET)}/, val.to_s, "Found secret in attribute #{key}")
    end

    # Check detail page
    get webhook_detail_path(webhook)
    assert_response :ok
    assert_no_match(/#{Regexp.escape(TEST_SECRET)}/, response.body)

    # Check home page
    get root_path
    assert_response :ok
    assert_no_match(/#{Regexp.escape(TEST_SECRET)}/, response.body)
  end

  # --- Receiver scenario tests ---

  test "verified request in 200 mode returns 200" do
    ReceiverSetting.set_response_mode("200")
    msg_id = "msg_mode_200"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
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
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "verified request in 204 mode returns empty 204 response" do
    ReceiverSetting.set_response_mode("204")
    msg_id = "msg_mode_204"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :no_content
    assert_empty response.body
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "verified request in 500 mode returns 500 but remains stored as verified" do
    ReceiverSetting.set_response_mode("500")
    msg_id = "msg_mode_500"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :internal_server_error
    json = JSON.parse(response.body)
    assert_match(/internal server error/i, json["error"])
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "verified request in 503 mode returns 503 but remains stored as verified" do
    ReceiverSetting.set_response_mode("503")
    msg_id = "msg_mode_503"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_match(/service unavailable/i, json["error"])
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "large response mode returns more than 4 KB" do
    ReceiverSetting.set_response_mode("large")
    msg_id = "msg_mode_large"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'
    sig = sign_payload(TEST_SECRET, msg_id, timestamp, payload)

    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => sig
      }

    assert_response :ok
    assert response.body.bytesize > 4096, "Expected response size > 4 KB, got #{response.body.bytesize} bytes"
    assert_equal "verified", ReceivedWebhook.last.verification_status
  end

  test "rejected requests ignore selected simulated response mode and always return 401" do
    ReceiverSetting.set_response_mode("500")
    msg_id = "msg_rejected_mode"
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"test.mode"}'

    # Missing signature header -> verification fails
    post webhook_path,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp
      }

    assert_response :unauthorized
    assert_equal "rejected", ReceivedWebhook.last.verification_status
  end

  # --- Polling endpoint tests ---

  test "GET /webhooks/recent returns HTML partial of recent webhooks with data-webhook-count" do
    ReceivedWebhook.create!(
      webhook_id: "wh_recent_poll",
      request_id: "req_recent_poll",
      event_type: "poll.event",
      headers: { "content-type" => "application/json" },
      body: '{"status":"polled"}',
      received_at: Time.current,
      verification_status: "verified",
      response_status: 200
    )

    get recent_webhooks_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-webhook-count]" do |elements|
      assert_equal ReceivedWebhook.count.to_s, elements.first["data-webhook-count"]
    end
    assert_select "code", text: "wh_recent_poll"
    assert_select ".badge-sig-verified", text: "Verified"
    assert_select ".badge-status-2xx", text: "Responded 200 OK"
  end

  test "changing response mode does not alter existing records" do
    # 1. Receive in 200 mode
    ReceiverSetting.set_response_mode("200")
    msg_id1 = "msg_rec_200"
    ts1 = Time.now.to_i.to_s
    payload1 = '{"type":"test.order"}'
    sig1 = sign_payload(TEST_SECRET, msg_id1, ts1, payload1)

    post webhook_path,
      params: payload1,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id1,
        "HTTP_WEBHOOK_TIMESTAMP" => ts1,
        "HTTP_WEBHOOK_SIGNATURE" => sig1
      }
    assert_response :ok
    wh1 = ReceivedWebhook.find_by(webhook_id: msg_id1)
    assert_equal 200, wh1.response_status

    # 2. Switch mode to 503
    ReceiverSetting.set_response_mode("503")
    msg_id2 = "msg_rec_503"
    ts2 = Time.now.to_i.to_s
    payload2 = '{"type":"test.retry"}'
    sig2 = sign_payload(TEST_SECRET, msg_id2, ts2, payload2)

    post webhook_path,
      params: payload2,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_WEBHOOK_ID" => msg_id2,
        "HTTP_WEBHOOK_TIMESTAMP" => ts2,
        "HTTP_WEBHOOK_SIGNATURE" => sig2
      }
    assert_response :service_unavailable
    wh2 = ReceivedWebhook.find_by(webhook_id: msg_id2)
    assert_equal 503, wh2.response_status

    # 3. Reload wh1 and ensure it is still 200
    wh1.reload
    assert_equal 200, wh1.response_status

    # 4. View in root_path and ensure both badges render correctly
    get root_path
    assert_response :success
    assert_select ".badge-status-2xx", text: "Responded 200 OK"
    assert_select ".badge-status-5xx", text: "Responded 503 Service Unavailable"
  end

  test "GET /webhooks/recent.json returns JSON response" do
    ReceivedWebhook.create!(
      webhook_id: "wh_json_test",
      body: '{"foo":"bar"}',
      received_at: Time.current + 1.minute,
      verification_status: "verified"
    )

    get recent_webhooks_path(format: :json)

    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("count")
    assert json.key?("webhooks")
    assert json["webhooks"].any? { |w| w["webhook_id"] == "wh_json_test" }
  end
end
