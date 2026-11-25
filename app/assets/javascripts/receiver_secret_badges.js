(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.HookReReceiverSecretBadges = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var ALLOWED_ROUTES = ["default", "success", "failure", "slow", "custom"];

  function isAllowedRoute(routeKey) {
    return ALLOWED_ROUTES.indexOf(String(routeKey)) !== -1;
  }

  // Returns true/false when the badge should be explicitly changed, or null
  // when the current server state must be preserved (non-2xx/network failure).
  function configuredFromResponse(response, data) {
    if (!response || response.ok !== true) {
      return null;
    }

    if (data && typeof data.configured === "boolean") {
      return data.configured;
    }

    return null;
  }

  function badgeForRoute(routeKey, scope) {
    if (!isAllowedRoute(routeKey)) {
      return null;
    }

    var root = scope || (typeof document !== "undefined" ? document : null);
    if (!root || typeof root.querySelector !== "function") {
      return null;
    }

    return root.querySelector('[data-receiver-secret-badge="' + routeKey + '"]');
  }

  function setBadgeConfigured(badge, configured) {
    if (!badge) {
      return;
    }

    if (configured) {
      badge.textContent = "Configured";
      badge.className = "badge badge-verified badge-sig-verified";
    } else {
      badge.textContent = "Not configured";
      badge.className = "badge badge-rejected badge-unconfigured";
    }
  }

  function updateRouteBadge(routeKey, configured, scope) {
    setBadgeConfigured(badgeForRoute(routeKey, scope), configured);
  }

  function initializeReceiverSecretUi(options) {
    options = options || {};
    var scope = options.document || (typeof document !== "undefined" ? document : null);
    var storage = options.localStorage || (typeof localStorage !== "undefined" ? localStorage : null);
    var request = options.fetch || (typeof fetch !== "undefined" ? fetch : null);

    if (!scope || !storage || !request || typeof scope.querySelectorAll !== "function") {
      return;
    }

    function csrfToken() {
      var token = scope.querySelector('meta[name="csrf-token"]');
      return token ? token.content : undefined;
    }

    function responseData(response) {
      return response.json().then(function(data) {
        return { response: response, data: data };
      });
    }

    scope.querySelectorAll("[data-receiver-secret-form]").forEach(function(form) {
      var routeKey = form.dataset.receiverRouteKey;
      var storageKey = form.dataset.receiverSecretStorageKey;
      var input = form.querySelector(".receiver-secret-input");
      var serverConfigured = form.dataset.serverConfigured === "true";

      if (!serverConfigured) {
        try {
          var savedSecret = storage.getItem(storageKey);
          if (savedSecret && savedSecret.trim().length > 0) {
            request(form.action, {
              method: "POST",
              headers: {
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
                "X-CSRF-Token": csrfToken()
              },
              body: "signing_secret=" + encodeURIComponent(savedSecret)
            })
            .then(responseData)
            .then(function(result) {
              var configured = configuredFromResponse(result.response, result.data);
              if (configured !== null) {
                updateRouteBadge(routeKey, configured, scope);
              }
            })
            .catch(function() {});
          }
        } catch (e) {}
      }

      form.addEventListener("submit", function() {
        if (input && input.value.trim().length > 0) {
          try { storage.setItem(storageKey, input.value.trim()); } catch (e) {}
        }
      });
    });

    scope.querySelectorAll(".clear-receiver-secret-btn").forEach(function(button) {
      button.addEventListener("click", function() {
        var routeKey = button.dataset.receiverRouteKey;
        var storageKey = button.dataset.receiverSecretStorageKey;
        var clearUrl = button.dataset.clearReceiverSecretUrl;

        request(clearUrl, {
          method: "DELETE",
          headers: {
            "Accept": "application/json",
            "X-CSRF-Token": csrfToken()
          }
        })
        .then(responseData)
        .then(function(result) {
          if (configuredFromResponse(result.response, result.data) === false) {
            try { storage.removeItem(storageKey); } catch (e) {}
            updateRouteBadge(routeKey, false, scope);
          }
        })
        .catch(function() {});
      });
    });
  }

  return {
    ALLOWED_ROUTES: ALLOWED_ROUTES,
    isAllowedRoute: isAllowedRoute,
    configuredFromResponse: configuredFromResponse,
    badgeForRoute: badgeForRoute,
    setBadgeConfigured: setBadgeConfigured,
    updateRouteBadge: updateRouteBadge,
    initializeReceiverSecretUi: initializeReceiverSecretUi
  };
});
