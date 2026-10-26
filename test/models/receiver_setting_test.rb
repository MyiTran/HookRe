require "test_helper"

class ReceiverSettingTest < ActiveSupport::TestCase
  test "default response mode is 200" do
    ReceiverSetting.delete_all
    assert_equal "200", ReceiverSetting.current_response_mode
  end

  test "set_response_mode updates and returns valid modes" do
    %w[200 204 500 503 large].each do |mode|
      result = ReceiverSetting.set_response_mode(mode)
      assert_equal mode, result
      assert_equal mode, ReceiverSetting.current_response_mode
    end
  end

  test "set_response_mode raises ArgumentError for invalid mode" do
    assert_raises(ArgumentError) do
      ReceiverSetting.set_response_mode("404")
    end
  end

  test "for_route initializes appropriate defaults for each route" do
    success = ReceiverSetting.for_route("success")
    assert_equal 200, success.status_code
    assert_equal 0, success.delay_seconds
    assert_equal "/webhooks/success", success.route_path
    assert_equal "Responding 200 OK", success.active_status_text
    assert_equal "badge-status-2xx", success.active_badge_class

    failure = ReceiverSetting.for_route("failure")
    assert_equal 500, failure.status_code
    assert_equal 0, failure.delay_seconds
    assert_equal "/webhooks/failure", failure.route_path
    assert_equal "Responding 500 Internal Server Error", failure.active_status_text
    assert_equal "badge-status-5xx", failure.active_badge_class

    slow = ReceiverSetting.for_route("slow")
    assert_equal 200, slow.status_code
    assert_equal 20, slow.delay_seconds
    assert_equal "/webhooks/slow", slow.route_path
    assert_equal "Responds after 20 seconds", slow.delay_label
  end

  test "validates status_code range between 100 and 599" do
    valid = ReceiverSetting.new(route_key: "custom", status_code: 429)
    assert valid.valid?

    low = ReceiverSetting.new(route_key: "custom", status_code: 99)
    assert_not low.valid?
    assert_includes low.errors[:status_code], "must be greater than or equal to 100"

    high = ReceiverSetting.new(route_key: "custom", status_code: 600)
    assert_not high.valid?
    assert_includes high.errors[:status_code], "must be less than or equal to 599"
  end

  test "validates delay_seconds between 0 and 60" do
    valid = ReceiverSetting.new(route_key: "custom", delay_seconds: 15)
    assert valid.valid?

    negative = ReceiverSetting.new(route_key: "custom", delay_seconds: -1)
    assert_not negative.valid?

    too_long = ReceiverSetting.new(route_key: "custom", delay_seconds: 61)
    assert_not too_long.valid?
  end

  test "validates response_body does not exceed 2 KB" do
    valid = ReceiverSetting.new(route_key: "custom", response_body: "a" * 2048)
    assert valid.valid?

    too_big = ReceiverSetting.new(route_key: "custom", response_body: "a" * 2049)
    assert_not too_big.valid?
    assert_includes too_big.errors[:response_body], "must not exceed 2 KB (2048 bytes)"
  end
end
