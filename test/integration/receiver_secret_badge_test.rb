require "test_helper"

class ReceiverSecretBadgeTest < ActionDispatch::IntegrationTest
  ROUTES = %w[success failure slow custom].freeze

  setup do
    SigningSecretStore.reset_to_default!
  end

  test "homepage resolves the receiver secret badge asset" do
    get root_path

    assert_response :success
    assert_select "script[src*='receiver_secret_badges']", 1

    asset_path = Rails.application.assets.load_path.find("receiver_secret_badges.js")
    assert asset_path.present?, "receiver_secret_badges.js must resolve through the Propshaft load path"
  end

  teardown do
    SigningSecretStore.reset_to_default!
  end

  test "JSON rehydrate save marks only the selected route configured and renders its badge" do
    post receiver_secret_path("success"),
      params: { signing_secret: "whsec_success_only" },
      headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal({ "configured" => true }, JSON.parse(response.body))

    assert SigningSecretStore.configured_for?("success")
    assert_not SigningSecretStore.configured_for?("failure")

    get root_path

    assert_select "span[data-receiver-secret-badge='success']", text: "Configured"
    assert_select "span[data-receiver-secret-badge='failure']", text: "Not configured"
  end

  test "non-2xx rehydrate keeps the selected route Not configured" do
    post "/receiver_secrets/other",
      params: { signing_secret: "whsec_should_not_save" },
      headers: { "Accept" => "application/json" }

    assert_response :not_found
    assert_not SigningSecretStore.configured_for?("success")

    get root_path

    assert_select "span[data-receiver-secret-badge='success']", text: "Not configured"
  end

  test "JSON clear updates only the current route and leaves other badges unchanged" do
    SigningSecretStore.set(route_key: "success", value: "whsec_success")
    SigningSecretStore.set(route_key: "failure", value: "whsec_failure")

    delete clear_receiver_secret_path("success"), headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal({ "configured" => false }, JSON.parse(response.body))
    assert_not SigningSecretStore.configured_for?("success")
    assert SigningSecretStore.configured_for?("failure")

    get root_path

    assert_select "span[data-receiver-secret-badge='success']", text: "Not configured"
    assert_select "span[data-receiver-secret-badge='failure']", text: "Configured"
  end

  test "rendered receiver badges expose allowlisted route identity and never render secrets" do
    secret = "whsec_never_render_me_123"
    SigningSecretStore.set(route_key: "success", value: secret)

    get root_path

    ROUTES.each do |route|
      assert_select "span[data-receiver-secret-badge='#{route}']", 1
    end

    assert_not_includes response.body, secret
  end

  test "JSON save response never includes the secret value" do
    secret = "whsec_json_no_leak_123"

    post receiver_secret_path("success"),
      params: { signing_secret: secret },
      headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal({ "configured" => true }, JSON.parse(response.body))
    assert_not_includes response.body, secret
  end
end
