require "test_helper"

class SigningSecretStoreTest < ActiveSupport::TestCase
  setup do
    SigningSecretStore.reset_to_default!
    @original_env = ENV["HOOKYARD_SIGNING_SECRET"]
    ENV.delete("HOOKYARD_SIGNING_SECRET")
  end

  teardown do
    SigningSecretStore.reset_to_default!
    if @original_env
      ENV["HOOKYARD_SIGNING_SECRET"] = @original_env
    else
      ENV.delete("HOOKYARD_SIGNING_SECRET")
    end
  end

  test "unconfigured by default when ENV is empty" do
    assert_not SigningSecretStore.configured_for?("success")
    assert_nil SigningSecretStore.secret_for("success")
  end

  test "uses HOOKYARD_SIGNING_SECRET only for the default route" do
    ENV["HOOKYARD_SIGNING_SECRET"] = "whsec_from_env_123"

    assert SigningSecretStore.configured_for?("default")
    assert_equal "whsec_from_env_123", SigningSecretStore.secret_for("default")
    assert_not SigningSecretStore.configured_for?("success")
    assert_nil SigningSecretStore.secret_for("success")
  end

  test "stores secrets independently by allowlisted route" do
    SigningSecretStore.set(route_key: "success", value: "whsec_success")
    SigningSecretStore.set(route_key: "failure", value: "whsec_failure")

    assert_equal "whsec_success", SigningSecretStore.secret_for("success")
    assert_equal "whsec_failure", SigningSecretStore.secret_for("failure")
    assert_nil SigningSecretStore.secret_for("slow")
  end

  test "clearing one route does not affect another route" do
    SigningSecretStore.set(route_key: "success", value: "whsec_success")
    SigningSecretStore.set(route_key: "failure", value: "whsec_failure")
    SigningSecretStore.clear(route_key: "success")

    assert_not SigningSecretStore.configured_for?("success")
    assert SigningSecretStore.configured_for?("failure")
    assert_equal "whsec_failure", SigningSecretStore.secret_for("failure")
  end

  test "rejects a route outside the allowlist" do
    assert_raises(ArgumentError) do
      SigningSecretStore.set(route_key: "other", value: "whsec_value")
    end
  end

  test "setting blank secret clears only its route" do
    SigningSecretStore.set(route_key: "success", value: "whsec_success")
    SigningSecretStore.set(route_key: "failure", value: "whsec_failure")
    SigningSecretStore.set(route_key: "success", value: "   ")

    assert_not SigningSecretStore.configured_for?("success")
    assert_equal "whsec_failure", SigningSecretStore.secret_for("failure")
  end
end

