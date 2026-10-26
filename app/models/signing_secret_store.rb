require "monitor"

class SigningSecretStore
  @lock = Monitor.new
  @manual_secret = nil
  @cleared = false

  class << self
    def secret
      @lock.synchronize do
        return nil if @cleared || $hookre_signing_secret_cleared
        @manual_secret.presence || $hookre_manual_secret.presence || ENV["HOOKYARD_SIGNING_SECRET"].presence
      end
    end

    def secrets
      raw = secret.to_s
      return [] if raw.blank?

      raw.split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
    end

    def set(value)
      @lock.synchronize do
        cleaned = value.to_s.strip.presence
        @manual_secret = cleaned
        $hookre_manual_secret = cleaned
        @cleared = cleaned.nil?
        $hookre_signing_secret_cleared = cleaned.nil?
        secret
      end
    end

    def clear
      @lock.synchronize do
        @manual_secret = nil
        $hookre_manual_secret = nil
        @cleared = true
        $hookre_signing_secret_cleared = true
      end
    end

    def configured?
      secret.present?
    end

    def reset_to_default!
      @lock.synchronize do
        @manual_secret = nil
        $hookre_manual_secret = nil
        @cleared = false
        $hookre_signing_secret_cleared = false
      end
    end
  end
end


