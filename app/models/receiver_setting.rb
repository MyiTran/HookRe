class ReceiverSetting < ApplicationRecord
  ROUTES = %w[success failure slow custom default].freeze
  PRESET_STATUSES = [200, 400, 408, 429, 500, 503].freeze
  VALID_MODES = %w[200 204 500 503 large fixed sequence].freeze
  RESPONSE_MODES = %w[fixed sequence].freeze

  validates :route_key, presence: true, uniqueness: true, inclusion: { in: ROUTES }
  validates :status_code, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }
  validates :delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 60 }
  validate :response_body_max_size
  validate :validate_sequence_steps

  def response_body_max_size
    return if response_mode == "large"

    if response_body.present? && response_body.to_s.bytesize > 2048
      errors.add(:response_body, "must not exceed 2 KB (2048 bytes)")
    end
  end

  def validate_sequence_steps
    return unless sequence_mode?

    steps = parsed_steps
    return if steps.empty?

    if steps.size > 20
      errors.add(:sequence_steps, "cannot exceed 20 steps")
    else
      steps.each_with_index do |s, idx|
        code = s["status_code"].to_i
        delay = s["delay_seconds"].to_i
        body = s["response_body"].to_s

        if code < 100 || code > 599
          errors.add(:sequence_steps, "step #{idx + 1} status code must be between 100 and 599")
        end
        if delay < 0 || delay > 60
          errors.add(:sequence_steps, "step #{idx + 1} delay must be between 0 and 60 seconds")
        end
        if body.bytesize > 2048
          errors.add(:sequence_steps, "step #{idx + 1} body must not exceed 2 KB")
        end
      end
    end
  end

  def sequence_mode?
    response_mode == "sequence"
  end

  def fixed_mode?
    !sequence_mode?
  end

  def parsed_steps
    raw = sequence_steps.presence || "[]"
    steps = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      []
    end
    steps.is_a?(Array) ? steps : []
  end

  def set_sequence_steps(steps_array)
    valid_steps = Array(steps_array).first(20).map do |s|
      code = s["status_code"] || s[:status_code]
      delay = s["delay_seconds"] || s[:delay_seconds]
      body = s["response_body"] || s[:response_body]

      {
        "status_code" => [[code.to_i, 100].max, 599].min,
        "delay_seconds" => [[delay.to_i, 0].max, 60].min,
        "response_body" => body.to_s.byteslice(0, 2048)
      }
    end
    self.sequence_steps = valid_steps.to_json
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
    if sequence_mode? && parsed_steps.any?
      steps = parsed_steps
      current_idx = [sequence_index.to_i, steps.size - 1].min
      step = steps[current_idx]
      step_num = current_idx + 1
      is_rep = (current_idx == steps.size - 1 && sequence_index.to_i >= steps.size - 1)
      rep_tag = is_rep ? " [Repeating]" : ""
      "Step #{step_num}/#{steps.size}#{rep_tag} (Next: #{step['status_code']})"
    else
      reason = Rack::Utils::HTTP_STATUS_CODES[status_code.to_i]
      reason.present? ? "Responding #{status_code} #{reason}" : "Responding #{status_code}"
    end
  end

  def active_badge_class
    if sequence_mode?
      "badge-status-4xx"
    else
      case status_code.to_i
      when 200..299 then "badge-status-2xx"
      when 400..499 then "badge-status-4xx"
      when 500..599 then "badge-status-5xx"
      else "badge-unconfigured"
      end
    end
  end

  def reset_sequence_progress!
    update_column(:sequence_index, 0)
  end

  def resolve_next_response!
    with_lock do
      if sequence_mode? && parsed_steps.any?
        steps = parsed_steps
        current_idx = [sequence_index.to_i, steps.size - 1].min
        step = steps[current_idx]
        step_number = current_idx + 1

        # Advance step; repeat final step if past end
        next_idx = [current_idx + 1, steps.size - 1].min
        update_column(:sequence_index, next_idx)

        {
          status_code: step["status_code"].to_i,
          delay_seconds: step["delay_seconds"].to_i,
          response_body: step["response_body"].presence,
          scenario_step: step_number,
          sequence_total: steps.size,
          repeating: (current_idx == steps.size - 1 && sequence_index.to_i >= steps.size - 1)
        }
      else
        # Fixed response mode
        {
          status_code: status_code.to_i,
          delay_seconds: delay_seconds.to_i,
          response_body: response_body.presence,
          scenario_step: nil
        }
      end
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
        s.sequence_steps = "[]"
        s.sequence_index = 0
        case key
        when "success"
          s.status_code = 200
          s.delay_seconds = 0
          s.response_mode = "200"
        when "failure"
          s.status_code = 500
          s.delay_seconds = 0
          s.response_mode = "500"
        when "slow"
          s.status_code = 200
          s.delay_seconds = 20
          s.response_mode = "200"
        when "custom"
          s.status_code = 200
          s.delay_seconds = 0
          s.response_mode = "200"
        else
          s.status_code = 200
          s.delay_seconds = 0
          s.response_mode = "200"
        end
      end
    end

    def normalize_route_key(key)
      k = key.to_s.sub(%r{^/webhooks/}, "").sub(%r{^/webhook}, "default").strip.downcase
      ROUTES.include?(k) ? k : "default"
    end

    def current_response_mode(route_key = "default")
      setting = for_route(route_key)
      if setting.sequence_mode?
        "sequence"
      elsif setting.response_mode.in?(%w[large 204 500 503 200])
        setting.response_mode
      else
        setting.status_code.to_s
      end
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
      when "fixed"
        setting.update!(response_mode: "fixed")
      when "sequence"
        setting.update!(response_mode: "sequence")
      end
      setting.response_mode
    end
  end
end
