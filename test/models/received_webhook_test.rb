require "test_helper"

class ReceivedWebhookTest < ActiveSupport::TestCase
  test "serializes and deserializes headers hash" do
    webhook = ReceivedWebhook.create!(
      webhook_id: "wh_test",
      headers: { "content-type" => "application/json", "webhook-id" => "wh_test" },
      body: "{}",
      verification_status: "verified"
    )

    webhook.reload
    assert_equal "application/json", webhook.headers["content-type"]
    assert_equal "wh_test", webhook.headers["webhook-id"]
    assert_equal "application/json", webhook.content_type
  end

  test "body_preview truncates appropriately" do
    long_body = "a" * 200
    webhook = ReceivedWebhook.new(body: long_body)
    assert_equal ("a" * 100) + "...", webhook.body_preview(100)

    short_body = "hello world"
    webhook_short = ReceivedWebhook.new(body: short_body)
    assert_equal "hello world", webhook_short.body_preview(100)
  end

  test "recent scope orders by received_at desc" do
    ReceivedWebhook.delete_all
    w1 = ReceivedWebhook.create!(webhook_id: "1", received_at: 2.hours.ago, verification_status: "verified")
    w2 = ReceivedWebhook.create!(webhook_id: "2", received_at: 1.hour.ago, verification_status: "verified")

    assert_equal [w2, w1], ReceivedWebhook.recent.to_a
  end

  test "verification helper methods" do
    verified = ReceivedWebhook.new(verification_status: "verified")
    assert verified.verified?
    assert_not verified.rejected?

    rejected = ReceivedWebhook.new(verification_status: "rejected")
    assert rejected.rejected?
    assert_not rejected.verified?
  end

  test "formatted_received_at converts UTC to Asia/Ho_Chi_Minh timezone format" do
    utc_time = Time.utc(2026, 10, 23, 4, 1, 18)
    webhook = ReceivedWebhook.new(received_at: utc_time)
    assert_equal "Oct 23, 2026, 11:01:18 GMT+7", webhook.formatted_received_at

    empty_webhook = ReceivedWebhook.new(received_at: nil)
    assert_equal "N/A", empty_webhook.formatted_received_at
  end

  test "response status helper methods" do
    wh_200 = ReceivedWebhook.new(response_status: 200)
    assert_equal "badge-status-2xx", wh_200.response_status_badge_class
    assert_equal "Responded 200", wh_200.response_status_text

    wh_204 = ReceivedWebhook.new(response_status: 204)
    assert_equal "badge-status-2xx", wh_204.response_status_badge_class
    assert_equal "Responded 204", wh_204.response_status_text

    wh_401 = ReceivedWebhook.new(response_status: 401)
    assert_equal "badge-status-4xx", wh_401.response_status_badge_class
    assert_equal "Responded 401", wh_401.response_status_text

    wh_500 = ReceivedWebhook.new(response_status: 500)
    assert_equal "badge-status-5xx", wh_500.response_status_badge_class
    assert_equal "Responded 500", wh_500.response_status_text

    wh_503 = ReceivedWebhook.new(response_status: 503)
    assert_equal "badge-status-5xx", wh_503.response_status_badge_class
    assert_equal "Responded 503", wh_503.response_status_text

    wh_none = ReceivedWebhook.new(response_status: nil)
    assert_equal "badge-unconfigured", wh_none.response_status_badge_class
    assert_nil wh_none.response_status_text
  end

  test "validates verification_status inclusion" do
    valid_record = ReceivedWebhook.new(verification_status: "verified")
    assert valid_record.valid?

    invalid_record = ReceivedWebhook.new(verification_status: "invalid_status")
    assert_not invalid_record.valid?
    assert_includes invalid_record.errors[:verification_status], "is not included in the list"
  end
end
