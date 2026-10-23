class ReceiverSetting < ApplicationRecord
  VALID_MODES = %w[200 204 500 503 large].freeze

  validates :response_mode, inclusion: { in: VALID_MODES }

  def self.current_response_mode
    setting = first
    setting ? setting.response_mode : "200"
  end

  def self.set_response_mode(mode)
    mode_str = mode.to_s
    raise ArgumentError, "Invalid response mode: #{mode}" unless VALID_MODES.include?(mode_str)

    setting = first_or_initialize
    setting.response_mode = mode_str
    setting.save!
    setting.response_mode
  end
end
