require "test_helper"
require "standardwebhooks"

class RouteSigningSecretTest < ActionDispatch::IntegrationTest
  ROUTES = %w[success failure slow custom].freeze

  setup do
    SigningSecretStore.reset_to_default!
    @secrets = ROUTES.to_h do |route|
      [route, "whsec_#{Base64.strict_encode64("receiver-secret-#{route}")}"]
    end
    ReceivedWebhook.delete_all
  end

  teardown do
    SigningSecretStore.reset_to_default!
  end

  test "each scenario route verifies only its configured secret" do
    ROUTES.each do |route|
      SigningSecretStore.set(route_key: route, value: @secrets.fetch(route))
    end

    ROUTES.each do |route|
      post signed_path(route), params: payload_for(route), headers: signed_headers(route, @secrets.fetch(route))

      assert_response expected_status_for(route)
      assert_equal "verified", ReceivedWebhook.last.verification_status
    end
  end

  test "a scenario secret is rejected by every other scenario route" do
    ROUTES.each do |route|
      SigningSecretStore.set(route_key: route, value: @secrets.fetch(route))
    end

    ROUTES.product(ROUTES).reject { |source, target| source == target }.each do |source, target|
      post signed_path(target), params: payload_for(target), headers: signed_headers(target, @secrets.fetch(source))

      assert_response :unauthorized
      assert_equal "rejected", ReceivedWebhook.last.verification_status
    end
  end

  test "a scenario route without a secret fails closed with 503" do
    post signed_path("success"), params: payload_for("success"), headers: signed_headers("success", @secrets.fetch("success"))

    assert_response :service_unavailable
    assert_equal "rejected", ReceivedWebhook.last.verification_status
    assert_equal 503, ReceivedWebhook.last.response_status
    assert_not_includes response.body, @secrets.fetch("success")
  end

  test "a scenario route with a missing or wrong signature returns 401" do
    SigningSecretStore.set(route_key: "success", value: @secrets.fetch("success"))

    post signed_path("success"), params: payload_for("success"), headers: {
      "CONTENT_TYPE" => "application/json",
      "HTTP_WEBHOOK_ID" => "msg_missing_signature",
      "HTTP_WEBHOOK_TIMESTAMP" => Time.now.to_i.to_s
    }

    assert_response :unauthorized
    assert_equal "rejected", ReceivedWebhook.last.verification_status

    post signed_path("success"), params: payload_for("success"), headers: signed_headers("success", @secrets.fetch("failure"))

    assert_response :unauthorized
    assert_equal "rejected", ReceivedWebhook.last.verification_status
  end

  test "an unverified request does not advance a route response scenario" do
    setting = ReceiverSetting.for_route("custom")
    setting.update!(response_mode: "sequence", sequence_index: 0)
    setting.set_sequence_steps([
      { status_code: 503, delay_seconds: 0 },
      { status_code: 200, delay_seconds: 0 }
    ])
    setting.save!
    SigningSecretStore.set(route_key: "custom", value: @secrets.fetch("custom"))

    post signed_path("custom"), params: payload_for("custom"), headers: {
      "CONTENT_TYPE" => "application/json",
      "HTTP_WEBHOOK_ID" => "msg_unverified_sequence",
      "HTTP_WEBHOOK_TIMESTAMP" => Time.now.to_i.to_s
    }

    assert_response :unauthorized
    assert_equal 0, setting.reload.sequence_index

    post signed_path("custom"), params: payload_for("custom"), headers: signed_headers("custom", @secrets.fetch("custom"))

    assert_response :service_unavailable
    assert_equal 1, setting.reload.sequence_index
  end

  test "clearing one route through settings does not clear another route" do
    SigningSecretStore.set(route_key: "success", value: @secrets.fetch("success"))
    SigningSecretStore.set(route_key: "failure", value: @secrets.fetch("failure"))

    delete "/receiver_secrets/success"

    assert_response :redirect
    assert_not SigningSecretStore.configured_for?("success")
    assert SigningSecretStore.configured_for?("failure")
  end

  test "settings rejects a route outside the receiver allowlist" do
    post "/receiver_secrets/other", params: { signing_secret: @secrets.fetch("success") }

    assert_response :not_found
    assert_not SigningSecretStore.configured_for?("success")
  end

  test "receiver tabs render separate blank secret inputs and route-scoped local storage keys" do
    SigningSecretStore.set(route_key: "success", value: @secrets.fetch("success"))

    get root_path

    assert_response :success
    ROUTES.each do |route|
      assert_select "form[data-receiver-secret-form='#{route}']", 1
      assert_select "form[data-receiver-secret-form='#{route}'] input[type='password']", 1
      assert_includes response.body, "hookre_endpoint_signing_secret_#{route}"
    end
    assert_not_includes response.body, "hookre_endpoint_signing_secret\";"
    assert_not_includes response.body, @secrets.fetch("success")
  end

  private

  def signed_path(route)
    "/webhooks/#{route}"
  end

  def payload_for(route)
    "{\"type\":\"receiver.#{route}\"}"
  end

  def signed_headers(route, secret)
    timestamp = Time.now.to_i.to_s
    payload = payload_for(route)
    webhook_id = "msg_#{route}_#{SecureRandom.hex(4)}"

    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_WEBHOOK_ID" => webhook_id,
      "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
      "HTTP_WEBHOOK_SIGNATURE" => StandardWebhooks::Webhook.new(secret).sign(webhook_id, timestamp, payload)
    }
  end

  def expected_status_for(route)
    route == "failure" ? :internal_server_error : :ok
  end
end
