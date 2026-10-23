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
    assert_not SigningSecretStore.configured?
    assert_nil SigningSecretStore.secret
  end

  test "uses HOOKYARD_SIGNING_SECRET ENV by default if set" do
    ENV["HOOKYARD_SIGNING_SECRET"] = "whsec_from_env_123"
    assert SigningSecretStore.configured?
    assert_equal "whsec_from_env_123", SigningSecretStore.secret
  end

  test "UI-set secret overrides ENV" do
    ENV["HOOKYARD_SIGNING_SECRET"] = "whsec_from_env_123"
    SigningSecretStore.set("whsec_manual_456")
    assert SigningSecretStore.configured?
    assert_equal "whsec_manual_456", SigningSecretStore.secret
  end

  test "clearing secret clears even when ENV is set" do
    ENV["HOOKYARD_SIGNING_SECRET"] = "whsec_from_env_123"
    SigningSecretStore.set("whsec_manual_456")
    SigningSecretStore.clear

    assert_not SigningSecretStore.configured?
    assert_nil SigningSecretStore.secret
  end

  test "setting blank secret clears the manual secret" do
    SigningSecretStore.set("whsec_manual_456")
    SigningSecretStore.set("   ")

    assert_not SigningSecretStore.configured?
    assert_nil SigningSecretStore.secret
  end
end

