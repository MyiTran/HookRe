require "test_helper"
require "net/http"

class SenderIntegrationTest < ActionDispatch::IntegrationTest
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

  test "submitting valid form uses POST-Redirect-GET and displays response" do
    mock_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    def mock_response.body; '{"received":true,"id":"evt_123"}'; end
    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      post send_event_path, params: {
        hookyard_url: "http://localhost:3000/api/v1/events",
        api_token: "test_token_abc",
        event_type: "invoice.paid",
        idempotency_key: "idemp_test_1",
        payload: '{"invoice_id":"INV-100","total":50000}'
      }

      # Verify POST -> Redirect -> GET (PRG)
      assert_redirected_to root_path
      follow_redirect!

      assert_response :success
      assert_select ".response-box.success", count: 1
      assert_select ".badge-200", text: /HTTP 200/
      assert_select "pre", text: /"received":true/

      assert_not_nil fake_http.captured_request
      assert_equal "Bearer test_token_abc", fake_http.captured_request["Authorization"]
      assert_equal "application/json", fake_http.captured_request["Content-Type"]

      # Subsequent GET refresh works cleanly without resubmission
      get root_path
      assert_response :success
    end
  end

  test "missing token behavior sends request without Authorization header" do
    mock_response = Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized")
    def mock_response.body; '{"error":"Missing or invalid API token"}'; end
    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      post send_event_path, params: {
        hookyard_url: "http://localhost:3000/api/v1/events",
        api_token: "",
        event_type: "order.created",
        idempotency_key: "idemp_no_token",
        payload: '{"order_id":"ORD-1"}'
      }

      assert_redirected_to root_path
      follow_redirect!

      assert_response :success
      assert_select ".response-box.error", count: 1
      assert_select ".badge-500", text: /HTTP 401/

      assert_not_nil fake_http.captured_request
      assert_nil fake_http.captured_request["Authorization"]
    end
  end

  test "HookYard non-2xx response displays error banner and status code" do
    mock_response = Net::HTTPUnprocessableEntity.new("1.1", "422", "Unprocessable Entity")
    def mock_response.body; '{"error":"Idempotency key reused with different payload"}'; end
    fake_http = FakeHttp.new(response: mock_response)

    with_fake_http(fake_http) do
      post send_event_path, params: {
        hookyard_url: "http://localhost:3000/api/v1/events",
        api_token: "test_token",
        event_type: "order.created",
        idempotency_key: "idemp_reuse",
        payload: '{"order_id":"ORD-2"}'
      }

      assert_redirected_to root_path
      follow_redirect!

      assert_response :success
      assert_select ".response-box.error", count: 1
      assert_select ".badge-500", text: /HTTP 422/
      assert_includes response.body, "Received non-2xx HTTP status 422"
      assert_includes response.body, "Idempotency key reused with different payload"
    end
  end

  test "submitting invalid JSON uses POST-Redirect-GET and shows validation error" do
    post send_event_path, params: {
      hookyard_url: "http://localhost:3000/api/v1/events",
      api_token: "test_token",
      event_type: "order.created",
      idempotency_key: "idemp_test_2",
      payload: "{ bad_json }"
    }

    # Verify PRG redirect
    assert_redirected_to root_path
    follow_redirect!

    assert_response :success
    assert_select ".response-box.error", count: 1
    assert_includes response.body, "Invalid JSON payload"
  end

  test "connection failure uses POST-Redirect-GET and is handled cleanly on page" do
    fake_http = FakeHttp.new(exception: Errno::ECONNREFUSED.new("Connection refused"))

    with_fake_http(fake_http) do
      post send_event_path, params: {
        hookyard_url: "http://localhost:3000/api/v1/events",
        api_token: "test_token",
        event_type: "order.created",
        idempotency_key: "idemp_test_3",
        payload: '{"order_id":"ORD-1"}'
      }

      # Verify PRG redirect
      assert_redirected_to root_path
      follow_redirect!

      assert_response :success
      assert_select ".response-box.error", count: 1
      assert_includes response.body, "Connection refused"
    end
  end
end
