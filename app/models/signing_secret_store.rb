require "monitor"

class SigningSecretStore
  @lock = Monitor.new
  @manual_secret = nil
  @cleared = false

  class << self
    def secret
      @lock.synchronize do
        return nil if @cleared
        @manual_secret.presence || ENV["HOOKYARD_SIGNING_SECRET"].presence
      end
    end

    def set(value)
      @lock.synchronize do
        cleaned = value.to_s.strip.presence
        @manual_secret = cleaned
        @cleared = cleaned.nil?
        secret
      end
    end

    def clear
      @lock.synchronize do
        @manual_secret = nil
        @cleared = true
      end
    end

    def configured?
      secret.present?
    end

    def reset_to_default!
      @lock.synchronize do
        @manual_secret = nil
        @cleared = false
      end
    end
  end
end

