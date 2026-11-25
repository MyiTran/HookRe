"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const badges = require("../../app/assets/javascripts/receiver_secret_badges.js");

function fakeResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    body,
    json() {
      return Promise.resolve(body);
    }
  };
}

function makeBadge(configured) {
  let currentText = configured ? "Configured" : "Not configured";
  let currentClass = configured
    ? "badge badge-verified badge-sig-verified"
    : "badge badge-rejected badge-unconfigured";

  return {
    set textContent(value) {
      currentText = value;
    },
    get textContent() {
      return currentText;
    },
    set className(value) {
      currentClass = value;
    },
    get className() {
      return currentClass;
    }
  };
}

function fakeScopeWithBadge(routeKey, badge) {
  const target = badge || makeBadge(false);

  return {
    target,
    querySelector(selector) {
      if (selector === `[data-receiver-secret-badge="${routeKey}"]`) {
        return target;
      }
      return null;
    }
  };
}

function fakeDocumentScope(badgesByRoute) {
  return {
    querySelector(selector) {
      const match = selector.match(/^\[data-receiver-secret-badge="([^"]+)"\]$/);
      if (!match) return null;
      return badgesByRoute[match[1]] || null;
    }
  };
}

function makeForm(routeKey, storageKey, serverConfigured) {
  const input = { value: "" };
  const listeners = {};

  return {
    action: `/receiver_secrets/${routeKey}`,
    dataset: {
      receiverRouteKey: routeKey,
      receiverSecretStorageKey: storageKey,
      serverConfigured: String(serverConfigured)
    },
    input,
    listeners,
    querySelector(selector) {
      if (selector === ".receiver-secret-input") return input;
      return null;
    },
    addEventListener(type, handler) {
      listeners[type] = handler;
    }
  };
}

function makeClearButton(routeKey, storageKey, clearUrl) {
  return {
    dataset: {
      receiverRouteKey: routeKey,
      receiverSecretStorageKey: storageKey,
      clearReceiverSecretUrl: clearUrl
    },
    listeners: {},
    addEventListener(type, handler) {
      this.listeners[type] = handler;
    }
  };
}

function makeUiScope(options) {
  const forms = options.forms || [];
  const clearButtons = options.clearButtons || [];
  const badgesByRoute = options.badgesByRoute || {};
  const csrfToken = options.csrfToken || "test-csrf-token";

  return {
    querySelectorAll(selector) {
      if (selector === "[data-receiver-secret-form]") return forms;
      if (selector === ".clear-receiver-secret-btn") return clearButtons;
      return [];
    },
    querySelector(selector) {
      if (selector === 'meta[name="csrf-token"]') return { content: csrfToken };
      const match = selector.match(/^\[data-receiver-secret-badge="([^"]+)"\]$/);
      if (match) return badgesByRoute[match[1]] || null;
      return null;
    }
  };
}

function makeStorage(initial) {
  const data = { ...(initial || {}) };

  return {
    data,
    getItem(key) {
      return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : null;
    },
    setItem(key, value) {
      data[key] = String(value);
    },
    removeItem(key) {
      delete data[key];
    }
  };
}

function flushPromises() {
  return new Promise((resolve) => setImmediate(resolve));
}

// Pure decision helpers

test("configuredFromResponse returns true for a 2xx rehydrate response", () => {
  assert.equal(badges.configuredFromResponse(fakeResponse(200, { configured: true }), { configured: true }), true);
});

test("configuredFromResponse returns false for a 2xx clear response", () => {
  assert.equal(badges.configuredFromResponse(fakeResponse(200, { configured: false }), { configured: false }), false);
});

test("configuredFromResponse keeps state unchanged for a 2xx response without an explicit configured flag", () => {
  assert.equal(badges.configuredFromResponse(fakeResponse(200, {}), {}), null);
});

test("configuredFromResponse keeps state unchanged for non-2xx responses", () => {
  assert.equal(badges.configuredFromResponse(fakeResponse(422, {}), { configured: false }), null);
  assert.equal(badges.configuredFromResponse(fakeResponse(500, {}), { configured: false }), null);
});

test("configuredFromResponse keeps state unchanged for a missing/network response", () => {
  assert.equal(badges.configuredFromResponse(null, undefined), null);
});

test("isAllowedRoute only accepts the server allowlist", () => {
  ["default", "success", "failure", "slow", "custom"].forEach((routeKey) => {
    assert.equal(badges.isAllowedRoute(routeKey), true, routeKey);
  });

  ["other", "attacker\"]", "success extra", "", null, undefined].forEach((routeKey) => {
    assert.equal(badges.isAllowedRoute(routeKey), false, String(routeKey));
  });
});

test("badgeForRoute ignores non-allowlisted route keys", () => {
  const scope = fakeScopeWithBadge("success");

  assert.equal(badges.badgeForRoute("success", scope), scope.target);
  assert.equal(badges.badgeForRoute("attacker\"]", scope), null);
});

test("badgeForRoute returns null when a route has no badge element", () => {
  const scope = fakeDocumentScope({ success: makeBadge(false) });

  assert.equal(badges.badgeForRoute("failure", scope), null);
});

test("badgeForRoute uses the provided scope and does not require a document", () => {
  const scope = fakeScopeWithBadge("slow", makeBadge(false));

  assert.equal(badges.badgeForRoute("slow", scope), scope.target);
});

test("setBadgeConfigured updates only the provided badge without leaking data", () => {
  const badge = makeBadge(false);

  badges.setBadgeConfigured(badge, true);
  assert.equal(badge.textContent, "Configured");
  assert.equal(badge.className, "badge badge-verified badge-sig-verified");

  badges.setBadgeConfigured(badge, false);
  assert.equal(badge.textContent, "Not configured");
  assert.equal(badge.className, "badge badge-rejected badge-unconfigured");
});

test("setBadgeConfigured is a no-op for a null or undefined badge", () => {
  assert.doesNotThrow(() => badges.setBadgeConfigured(null, true));
  assert.doesNotThrow(() => badges.setBadgeConfigured(undefined, false));
});

test("updateRouteBadge only updates the matching allowlisted badge", () => {
  const successScope = fakeScopeWithBadge("success");
  const failureScope = fakeScopeWithBadge("failure");

  badges.updateRouteBadge("success", true, successScope);
  badges.updateRouteBadge("failure", false, failureScope);

  assert.equal(successScope.target.textContent, "Configured");
  assert.equal(failureScope.target.textContent, "Not configured");
});

test("updateRouteBadge is a no-op for non-allowlisted route keys", () => {
  const scope = fakeScopeWithBadge("success");

  badges.updateRouteBadge("attacker\"]", true, scope);

  assert.equal(scope.target.textContent, "Not configured");
});

// Full UI initialization flows

test("rehydrate success updates the correct route badge to Configured", async () => {
  const badge = makeBadge(false);
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", false);
  const scope = makeUiScope({ forms: [form], badgesByRoute: { success: badge } });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });
  const calls = [];
  const fetch = (url, options) => {
    calls.push({ url, options });
    return Promise.resolve(fakeResponse(200, { configured: true }));
  };

  badges.initializeReceiverSecretUi({ document: scope, localStorage: storage, fetch });
  await flushPromises();

  assert.equal(badge.textContent, "Configured");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/receiver_secrets/success");
});

test("rehydrate non-2xx keeps the route badge Not configured", async () => {
  const badge = makeBadge(false);
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", false);
  const scope = makeUiScope({ forms: [form], badgesByRoute: { success: badge } });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => Promise.resolve(fakeResponse(500, { configured: false }))
  });
  await flushPromises();

  assert.equal(badge.textContent, "Not configured");
});

test("rehydrate network failure keeps the route badge Not configured", async () => {
  const badge = makeBadge(false);
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", false);
  const scope = makeUiScope({ forms: [form], badgesByRoute: { success: badge } });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => Promise.reject(new Error("network"))
  });
  await flushPromises();

  assert.equal(badge.textContent, "Not configured");
});

test("rehydrate does not run when the server already has the route configured", async () => {
  const badge = makeBadge(true);
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", true);
  const scope = makeUiScope({ forms: [form], badgesByRoute: { success: badge } });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });
  let fetchCalls = 0;

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => {
      fetchCalls += 1;
      return Promise.resolve(fakeResponse(200, { configured: true }));
    }
  });
  await flushPromises();

  assert.equal(fetchCalls, 0);
  assert.equal(badge.textContent, "Configured");
});

test("rehydrate ignores a route with no stored secret", async () => {
  const badge = makeBadge(false);
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", false);
  const scope = makeUiScope({ forms: [form], badgesByRoute: { success: badge } });
  const storage = makeStorage({});
  let fetchCalls = 0;

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => {
      fetchCalls += 1;
      return Promise.resolve(fakeResponse(200, { configured: true }));
    }
  });
  await flushPromises();

  assert.equal(fetchCalls, 0);
  assert.equal(badge.textContent, "Not configured");
});

test("clear success updates only the current route badge and removes its stored secret", async () => {
  const successBadge = makeBadge(true);
  const failureBadge = makeBadge(true);
  const clearButton = makeClearButton(
    "success",
    "hookre_endpoint_signing_secret_success",
    "/receiver_secrets/success"
  );
  const scope = makeUiScope({
    clearButtons: [clearButton],
    badgesByRoute: { success: successBadge, failure: failureBadge }
  });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => Promise.resolve(fakeResponse(200, { configured: false }))
  });

  clearButton.listeners.click();
  await flushPromises();

  assert.equal(successBadge.textContent, "Not configured");
  assert.equal(failureBadge.textContent, "Configured");
  assert.equal(storage.getItem("hookre_endpoint_signing_secret_success"), null);
});

test("clear non-2xx keeps the badge and stored secret unchanged", async () => {
  const badge = makeBadge(true);
  const clearButton = makeClearButton(
    "success",
    "hookre_endpoint_signing_secret_success",
    "/receiver_secrets/success"
  );
  const scope = makeUiScope({ clearButtons: [clearButton], badgesByRoute: { success: badge } });
  const storage = makeStorage({ hookre_endpoint_signing_secret_success: "whsec_abc" });

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: () => Promise.resolve(fakeResponse(500, { configured: false }))
  });

  clearButton.listeners.click();
  await flushPromises();

  assert.equal(badge.textContent, "Configured");
  assert.equal(storage.getItem("hookre_endpoint_signing_secret_success"), "whsec_abc");
});

test("save submit stores the entered secret for the route without echoing it to the input", () => {
  const form = makeForm("success", "hookre_endpoint_signing_secret_success", true);
  const scope = makeUiScope({ forms: [form], badgesByRoute: {} });
  const storage = makeStorage({});

  badges.initializeReceiverSecretUi({ document: scope, localStorage: storage, fetch: () => {} });

  form.input.value = "whsec_new_value";
  form.listeners.submit();

  assert.equal(storage.getItem("hookre_endpoint_signing_secret_success"), "whsec_new_value");
  assert.equal(form.input.value, "whsec_new_value");
});

test("cross-route rehydrate only updates the route with a stored secret", async () => {
  const successBadge = makeBadge(false);
  const failureBadge = makeBadge(false);
  const successForm = makeForm("success", "hookre_endpoint_signing_secret_success", false);
  const failureForm = makeForm("failure", "hookre_endpoint_signing_secret_failure", false);
  const scope = makeUiScope({
    forms: [successForm, failureForm],
    badgesByRoute: { success: successBadge, failure: failureBadge }
  });
  const storage = makeStorage({
    hookre_endpoint_signing_secret_success: "whsec_success"
  });

  badges.initializeReceiverSecretUi({
    document: scope,
    localStorage: storage,
    fetch: (url) => Promise.resolve(fakeResponse(200, { configured: true }))
  });
  await flushPromises();

  assert.equal(successBadge.textContent, "Configured");
  assert.equal(failureBadge.textContent, "Not configured");
});
