require "test_helper"

class WebhookListAndDetailTest < ActionDispatch::IntegrationTest
  setup do
    ReceivedWebhook.delete_all
  end

  test "home page lists webhooks newest first with verification and response status badges" do
    ReceivedWebhook.create!(
      webhook_id: "wh_older",
      request_id: "req_older",
      headers: { "content-type" => "application/json" },
      body: '{"message":"older webhook"}',
      received_at: 10.minutes.ago,
      verification_status: "verified",
      response_status: 200
    )

    ReceivedWebhook.create!(
      webhook_id: "wh_newer",
      request_id: "req_newer",
      headers: { "content-type" => "application/json" },
      body: '{"message":"newer webhook"}',
      received_at: 1.minute.ago,
      verification_status: "rejected",
      verification_error: "No matching signature found",
      response_status: 401
    )

    get root_path
    assert_response :success

    # Ensure both webhooks are displayed
    assert_includes response.body, "wh_older"
    assert_includes response.body, "wh_newer"

    # Verify order: newer webhook appears before older webhook in response body
    pos_newer = response.body.index("wh_newer")
    pos_older = response.body.index("wh_older")
    assert pos_newer < pos_older, "Expected newest webhook to appear first in HTML"

    assert_select ".badge-sig-verified", text: "Verified"
    assert_select ".badge-sig-invalid", text: "Invalid signature"
    assert_select ".badge-status-2xx", text: "Responded 200 OK"
    assert_select ".badge-status-4xx", text: "Responded 401 Unauthorized"
    assert_includes response.body, "GMT+7"
  end

  test "detail displays stored request with verification info and response status" do
    utc_time = Time.utc(2026, 10, 23, 4, 1, 18)
    webhook = ReceivedWebhook.create!(
      webhook_id: "wh_detail_test",
      request_id: "req_detail_test",
      event_type: "customer.subscription.created",
      headers: {
        "webhook-id" => "wh_detail_test",
        "webhook-signature" => "v1,sig_secret",
        "content-type" => "application/json"
      },
      body: '{"customer_id":"cust_99","plan":"pro"}',
      received_at: utc_time,
      verification_status: "rejected",
      verification_error: "Message timestamp too old",
      response_status: 401
    )

    get webhook_detail_path(webhook)
    assert_response :success

    assert_select ".badge-sig-invalid", text: "Invalid signature"
    assert_select ".badge-status-4xx", text: "Responded 401 Unauthorized"
    assert_select "td", text: /Message timestamp too old/
    assert_select "code", text: "wh_detail_test"
    assert_select "code", text: "req_detail_test"
    assert_select "code", text: "customer.subscription.created"
    assert_select "pre", text: /v1,sig_secret/
    assert_select "pre", text: '{"customer_id":"cust_99","plan":"pro"}'
    assert_includes response.body, "Oct 23, 2026, 11:01:18 GMT+7"
  end
end
