class ReceivedWebhook < ApplicationRecord
  serialize :headers, coder: JSON

  scope :recent, -> { order(received_at: :desc, id: :desc) }

  STATUS_VERIFIED = "verified"
  STATUS_REJECTED = "rejected"

  validates :verification_status, inclusion: { in: [STATUS_VERIFIED, STATUS_REJECTED] }, allow_nil: true

  def verified?
    verification_status == STATUS_VERIFIED
  end

  def rejected?
    verification_status == STATUS_REJECTED
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
