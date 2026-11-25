require "monitor"

class SigningSecretStore
  ROUTE_KEYS = %w[default success failure slow custom].freeze

  @lock = Monitor.new
  @manual_secrets = {}
  @cleared_routes = {}

  class << self
    def valid_route_key?(route_key)
      ROUTE_KEYS.include?(route_key.to_s)
    end

    def secret_for(route_key)
      key = validate_route_key!(route_key)

      @lock.synchronize do
        return nil if cleared_routes[key]

        manual_secrets[key].presence || default_secret_for(key)
      end
    end

    def secrets_for(route_key)
      secret = secret_for(route_key)
      secret.present? ? [secret] : []
    end

    def configured_for?(route_key)
      secret_for(route_key).present?
    end

    def set(value = nil, route_key: "default", **options)
      key = validate_route_key!(route_key)
      value = options[:value] if options.key?(:value)
      cleaned = value.to_s.strip.presence

      @lock.synchronize do
        if cleaned
          manual_secrets[key] = cleaned
          cleared_routes.delete(key)
        else
          manual_secrets.delete(key)
          cleared_routes[key] = true
        end
      end
    end

    def clear(route_key: "default")
      key = validate_route_key!(route_key)

      @lock.synchronize do
        manual_secrets.delete(key)
        cleared_routes[key] = true
      end
    end

    def secret
      secret_for("default")
    end

    def secrets
      secrets_for("default")
    end

    def configured?
      configured_for?("default")
    end

    def reset_to_default!
      @lock.synchronize do
        @manual_secrets = {}
        @cleared_routes = {}
      end
    end

    private

    def validate_route_key!(route_key)
      key = route_key.to_s
      return key if valid_route_key?(key)

      raise ArgumentError, "Invalid receiver route"
    end

    def default_secret_for(route_key)
      ENV["HOOKYARD_SIGNING_SECRET"].presence if route_key == "default"
    end

    def manual_secrets
      @manual_secrets ||= {}
    end

    def cleared_routes
      @cleared_routes ||= {}
    end
  end
end


