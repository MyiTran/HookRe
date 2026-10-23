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
end
