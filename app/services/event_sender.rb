require "net/http"
require "uri"
require "json"

class EventSender
  Result = Struct.new(:success, :status_code, :body, :error, keyword_init: true) do
    def success?
      success
    end
  end

  attr_reader :url, :token, :event_type, :idempotency_key, :payload_json

  def initialize(url:, token:, event_type:, idempotency_key:, payload_json:)
    @url = url.to_s.strip
    @token = token.to_s.strip
    @event_type = event_type.to_s.strip
    @idempotency_key = idempotency_key.to_s.strip
    @payload_json = payload_json.to_s.strip
  end

  def call
    # 1. Validate payload JSON
    parsed_payload = begin
      JSON.parse(payload_json)
    rescue JSON::ParserError => e
      return Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Invalid JSON payload: #{e.message}"
      )
    end

    # 2. Validate URL
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError => e
      return Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Invalid HookYard API URL: #{e.message}"
      )
    end

    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Invalid HookYard API URL: Must start with http:// or https://"
      )
    end

    # 3. Build request body
    request_body = {
      event_type: event_type,
      idempotency_key: idempotency_key,
      payload: parsed_payload
    }.to_json

    # 4. Send HTTP request using Net::HTTP
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 5
    http.read_timeout = 10

    path = uri.request_uri.presence || "/"
    request = Net::HTTP::Post.new(path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{token}" if token.present?
    request.body = request_body

    begin
      response = http.request(request)
      status = response.code.to_i
      is_success = status.between?(200, 299)

      Result.new(
        success: is_success,
        status_code: status,
        body: response.body,
        error: is_success ? nil : "Received non-2xx HTTP status #{status} from HookYard"
      )
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Request timed out: #{e.message}"
      )
    rescue Errno::ECONNREFUSED => e
      Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Connection refused (#{uri.host}:#{uri.port}): #{e.message}"
      )
    rescue SocketError, Errno::EHOSTUNREACH => e
      Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "Connection failed: #{e.message}"
      )
    rescue StandardError => e
      Result.new(
        success: false,
        status_code: nil,
        body: nil,
        error: "HTTP error: #{e.class} - #{e.message}"
      )
    end
  end
end

