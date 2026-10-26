class ReceiverSetting < ApplicationRecord
  ROUTES = %w[success failure slow custom default].freeze
  PRESET_STATUSES = [200, 400, 408, 429, 500, 503].freeze
  VALID_MODES = %w[200 204 500 503 large].freeze

  validates :route_key, presence: true, uniqueness: true, inclusion: { in: ROUTES }
  validates :status_code, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }
  validates :delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 60 }
  validate :response_body_max_size

  def response_body_max_size
    return if response_mode == "large"

    if response_body.present? && response_body.to_s.bytesize > 2048
      errors.add(:response_body, "must not exceed 2 KB (2048 bytes)")
    end
  end

  def route_path
    case route_key
    when "default" then "/webhook"
    else "/webhooks/#{route_key}"
    end
  end

  def route_label
    case route_key
    when "success" then "Success receiver"
    when "failure" then "Failure receiver"
    when "slow"    then "Slow receiver"
    when "custom"  then "Custom receiver"
    when "default" then "Default receiver"
    else "#{route_key.capitalize} receiver"
    end
  end

  def active_status_text
    reason = Rack::Utils::HTTP_STATUS_CODES[status_code.to_i]
    reason.present? ? "Responding #{status_code} #{reason}" : "Responding #{status_code}"
  end

  def active_badge_class
    case status_code.to_i
    when 200..299 then "badge-status-2xx"
    when 400..499 then "badge-status-4xx"
    when 500..599 then "badge-status-5xx"
    else "badge-unconfigured"
    end
  end

  def delay_label
    return nil if delay_seconds.to_i <= 0

    "Responds after #{delay_seconds} seconds"
  end

  class << self
    def for_route(route_key)
      key = normalize_route_key(route_key)
      find_or_create_by!(route_key: key) do |s|
        case key
        when "success"
          s.status_code = 200
          s.delay_seconds = 0
        when "failure"
          s.status_code = 500
          s.delay_seconds = 0
        when "slow"
          s.status_code = 200
          s.delay_seconds = 20
        when "custom"
          s.status_code = 200
          s.delay_seconds = 0
        else
          s.status_code = 200
          s.delay_seconds = 0
        end
      end
    end

    def normalize_route_key(key)
      k = key.to_s.sub(%r{^/webhooks/}, "").sub(%r{^/webhook}, "default").strip.downcase
      ROUTES.include?(k) ? k : "default"
    end

    def current_response_mode(route_key = "default")
      setting = for_route(route_key)
      setting.response_mode.presence || setting.status_code.to_s
    end

    def set_response_mode(mode, route_key = "default")
      mode_str = mode.to_s
      raise ArgumentError, "Invalid response mode: #{mode}" unless VALID_MODES.include?(mode_str)

      setting = for_route(route_key)
      case mode_str
      when "200"
        setting.update!(status_code: 200, delay_seconds: 0, response_body: nil, response_mode: "200")
      when "204"
        setting.update!(status_code: 204, delay_seconds: 0, response_body: nil, response_mode: "204")
      when "500"
        setting.update!(status_code: 500, delay_seconds: 0, response_body: nil, response_mode: "500")
      when "503"
        setting.update!(status_code: 503, delay_seconds: 0, response_body: nil, response_mode: "503")
      when "large"
        setting.update!(status_code: 200, delay_seconds: 0, response_body: "X" * 5000, response_mode: "large")
      end
      setting.response_mode
    end
  end
end
