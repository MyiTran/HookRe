class ReceivedWebhook < ApplicationRecord
  serialize :headers, coder: JSON

  scope :recent, -> { order(received_at: :desc, id: :desc) }
  scope :for_route, ->(route_key) {
    case route_key.to_s.downcase
    when "success" then where(receiver_path: "/webhooks/success")
    when "failure" then where(receiver_path: "/webhooks/failure")
    when "slow"    then where(receiver_path: "/webhooks/slow")
    when "custom"  then where(receiver_path: "/webhooks/custom")
    when "default" then where(receiver_path: ["/webhook", nil])
    else all
    end
  }

  STATUS_VERIFIED = "verified"
  STATUS_REJECTED = "rejected"
  STATUS_NOT_VERIFIED = "not_verified"

  validates :verification_status, inclusion: { in: [STATUS_VERIFIED, STATUS_REJECTED, STATUS_NOT_VERIFIED] }, allow_nil: true

  def verified?
    verification_status == STATUS_VERIFIED
  end

  def rejected?
    verification_status == STATUS_REJECTED
  end

  def not_verified?
    verification_status == STATUS_NOT_VERIFIED || verification_status.blank? || verification_error&.include?("not configured")
  end

  def signature_status_text
    if verified?
      "Verified"
    elsif rejected? && !verification_error&.include?("not configured")
      "Invalid signature"
    else
      "Not verified"
    end
  end

  def signature_status_badge_class
    if verified?
      "badge-sig-verified"
    elsif rejected? && !verification_error&.include?("not configured")
      "badge-sig-invalid"
    else
      "badge-unconfigured"
    end
  end

  def delayed?
    delay_seconds.to_i > 0
  end

  def scenario_step?
    scenario_step.present? && scenario_step.to_i > 0
  end

  def scenario_step_text
    "Scenario step #{scenario_step}"
  end

  def display_receiver_path
    receiver_path.presence || "/webhook"
  end

  def formatted_received_at
    return "N/A" if received_at.blank?

    received_at.in_time_zone("Asia/Ho_Chi_Minh").strftime("%b %d, %Y, %H:%M:%S GMT+7")
  end

  def response_status_badge_class
    case response_status.to_i
    when 200..299 then "badge-status-2xx"
    when 400..499 then "badge-status-4xx"
    when 500..599 then "badge-status-5xx"
    else "badge-unconfigured"
    end
  end

  def response_status_text
    return "Response not recorded" if response_status.blank?

    reason = Rack::Utils::HTTP_STATUS_CODES[response_status.to_i]
    if reason.present?
      "Responded #{response_status} #{reason}"
    else
      "Responded #{response_status}"
    end
  end

  def content_type
    headers&.dig("content-type") || headers&.dig("Content-Type") || "application/json"
  end

  def body_preview(limit = 100)
    return "" if body.blank?
    body.length > limit ? "#{body[0...limit]}..." : body
  end
end
