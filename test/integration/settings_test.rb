require "test_helper"

class SettingsTest < ActionDispatch::IntegrationTest
  setup do
    SigningSecretStore.reset_to_default!
  end

  teardown do
    SigningSecretStore.reset_to_default!
  end

  test "POST /response_mode updates response mode" do
    ReceiverSetting.set_response_mode("200")
    assert_equal "200", ReceiverSetting.current_response_mode

    %w[204 500 503 large 200].each do |mode|
      post response_mode_path, params: { response_mode: mode }
      assert_redirected_to root_path
      follow_redirect!

      assert_equal mode, ReceiverSetting.current_response_mode
    end
  end

  test "POST /response_mode rejects invalid mode" do
    ReceiverSetting.set_response_mode("200")
    post response_mode_path, params: { response_mode: "418" }
    assert_redirected_to root_path
    follow_redirect!

    assert_equal "200", ReceiverSetting.current_response_mode
    assert_select ".flash-alert", text: /Invalid response mode/
  end

  test "POST /signing_secret sets signing secret in memory" do
    assert_not SigningSecretStore.configured?

    post signing_secret_path, params: { signing_secret: "whsec_test_secret_abc123" }
    assert_redirected_to root_path
    follow_redirect!

    assert SigningSecretStore.configured?
    assert_equal "whsec_test_secret_abc123", SigningSecretStore.secret
    assert_select ".badge-verified", text: "Configured"

    # Ensure secret is NOT in rendered HTML
    assert_no_match(/whsec_test_secret_abc123/, response.body)
  end

  test "DELETE /signing_secret clears signing secret" do
    SigningSecretStore.set("whsec_to_be_cleared")
    assert SigningSecretStore.configured?

    delete clear_signing_secret_path
    assert_redirected_to root_path
    follow_redirect!

    assert_not SigningSecretStore.configured?
    assert_nil SigningSecretStore.secret
    assert_select ".badge-rejected", text: "Not configured"
  end
end
