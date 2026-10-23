require "test_helper"

class EventSenderTest < ActiveSupport::TestCase
  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :captured_request

    def initialize(response: nil, exception: nil)
      @response = response
      @exception = exception
    end

    def request(req)
      @captured_request = req
      raise @exception if @exception
      @response
    end
  end

  def with_fake_http(fake_http)
    singleton_class = class << Net::HTTP; self; end
    original_new = Net::HTTP.method(:new)
    singleton_class.send(:define_method, :new) { |*_args| fake_http }
    yield
  ensure
    singleton_class.send(:define_method, :new, original_new)
  end

  test "valid JSON builds expected HookYard request" do
    sender = EventSender.new(
      url: "http://localhost:3000/api/v1/events",
      token: "secret_token_123",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: '{"order_id":"ORD-123","amount":5000}'
    )

    mock_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    def mock_response.body; '{"status":"ok"}'; end

    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      result = sender.call
      assert result.success?
      assert_equal 200, result.status_code
      assert_equal '{"status":"ok"}', result.body
      assert_nil result.error

      captured = fake_http.captured_request
      assert_equal "application/json", captured["Content-Type"]
      assert_equal "Bearer secret_token_123", captured["Authorization"]

      body_data = JSON.parse(captured.body)
      assert_equal "order.created", body_data["event_type"]
      assert_equal "idemp_abc", body_data["idempotency_key"]
      assert_equal({ "order_id" => "ORD-123", "amount" => 5000 }, body_data["payload"])
    end
  end

  test "missing token behavior: does not set Authorization header" do
    sender = EventSender.new(
      url: "http://localhost:3000/api/v1/events",
      token: "",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: '{"order_id":"ORD-123"}'
    )

    mock_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    def mock_response.body; '{"status":"ok"}'; end
    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      result = sender.call
      assert result.success?
      assert_nil fake_http.captured_request["Authorization"]
    end
  end

  test "invalid JSON shows validation error" do
    sender = EventSender.new(
      url: "http://localhost:3000/api/v1/events",
      token: "token",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: "{ invalid json }"
    )

    result = sender.call
    assert_not result.success?
    assert_includes result.error, "Invalid JSON payload"
  end

  test "connection failure handled cleanly" do
    sender = EventSender.new(
      url: "http://localhost:9999/api/v1/events",
      token: "token",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: '{"order_id":"ORD-123"}'
    )

    fake_http = FakeHttp.new(exception: Errno::ECONNREFUSED.new("Connection refused"))

    with_fake_http(fake_http) do
      result = sender.call
      assert_not result.success?
      assert_includes result.error, "Connection refused"
    end
  end

  test "timeout handled cleanly" do
    sender = EventSender.new(
      url: "http://localhost:3000/api/v1/events",
      token: "token",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: '{"order_id":"ORD-123"}'
    )

    fake_http = FakeHttp.new(exception: Net::ReadTimeout.new("Read timed out"))

    with_fake_http(fake_http) do
      result = sender.call
      assert_not result.success?
      assert_includes result.error, "Request timed out"
    end
  end

  test "non-2xx response from HookYard handled cleanly" do
    sender = EventSender.new(
      url: "http://localhost:3000/api/v1/events",
      token: "token",
      event_type: "order.created",
      idempotency_key: "idemp_abc",
      payload_json: '{"order_id":"ORD-123"}'
    )

    mock_response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    def mock_response.body; '{"error":"missing required field"}'; end
    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      result = sender.call
      assert_not result.success?
      assert_equal 400, result.status_code
      assert_equal '{"error":"missing required field"}', result.body
      assert_includes result.error, "Received non-2xx HTTP status 400"
    end
  end
end
