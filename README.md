# HookRe - HookYard Phase 5 E2E Testing Harness

HookRe is a dedicated Ruby on Rails MVC manual testing harness designed to verify HookYard's Phase 5 milestones:
- Event ingestion (`POST /api/v1/events`)
- Fan-out to subscriptions
- Standard Webhooks signed delivery (`POST /webhook`)
- Response evidence capture (status, headers, body truncation)
- Endpoint signing-secret rotation and verification

HookRe fulfills two core roles:
1. **Sender**: Dispatches test events to the HookYard API with `Authorization: Bearer <Project API Token>`.
2. **Receiver**: Receives signed webhooks, verifies signatures with the official `standardwebhooks` library, records verification status/evidence, and allows simulating response status codes (200, 204, 500, 503, large payload).

---

## Setup & Startup

```bash
bundle install
bin/rails db:prepare
bin/rails server -p 3001
```

> **Port Note:** HookYard runs on port `3000`, so HookRe runs on port `3001`.

### Host Authorization & ngrok

HookYard blocks localhost and private IP addresses for webhook destinations to prevent SSRF. In development, HookRe must be exposed via a public HTTPS tunnel such as [ngrok](https://ngrok.com/).

Rails development host authorization is pre-configured to allow:
- `*.ngrok-free.app`
- `*.ngrok-free.dev`
- `*.ngrok.io`
- `*.ngrok.app`
- `*.ngrok.dev`
- Custom host via `PUBLIC_HOST` environment variable (e.g. `PUBLIC_HOST=my-tunnel.example.com bin/rails server -p 3001`)

---

## Complete Phase 5 Manual E2E Verification Flow

Follow this exact step-by-step checklist to test HookYard Phase 5:

### 1. Start HookRe and ngrok
1. Start HookRe on port 3001:
   ```bash
   bin/rails server -p 3001
   ```
2. Start ngrok in a separate terminal to expose port 3001:
   ```bash
   ngrok http 3001
   ```
3. Copy the public HTTPS forwarding URL from ngrok (e.g., `https://abc-123.ngrok-free.app`).

### 2. Configure HookYard Endpoint & Signing Secret
4. Start HookYard's dependencies and services (PostgreSQL, Redis, Sidekiq, Rails server on port 3000).
5. In HookYard, create an active, non-archived Endpoint with:
   - **URL**: `https://<your-ngrok-subdomain>.ngrok-free.app/webhook`
   - **Event types**: Subscribe to `order.created` or `*`.
6. Copy the one-time Endpoint signing secret displayed by HookYard (format: `whsec_...`).
7. Open HookRe at [http://localhost:3001](http://localhost:3001). Under the **Receiver** card, paste the secret into the **Endpoint Signing Secret** field and click **Save Secret**. Verify the badge displays **Configured**.
   *(Note: Secrets are stored strictly in memory for the running Rails process, per receiver route, and are never persisted to database, cookies, or logs. This is a process-local store: it is not shared across Rails workers/processes, so use a single worker for multi-route secret testing. You can also specify `HOOKYARD_SIGNING_SECRET=whsec_...` at boot for the default route.)*

### 3. Send Event & Verify Delivery
8. Copy your HookYard **Project API Token** into the HookRe **Sender** form.
9. Enter event details:
   - **HookYard API URL**: `http://localhost:3000/api/v1/events`
   - **Event Type**: `order.created`
   - **Idempotency Key**: Use a unique key (e.g. `evt_test_001`)
   - **Payload**: `{"order_id": "ORD-001", "amount": 120000}`
10. Click **Send Event**. Confirm HookYard returns HTTP 202/200 Accepted with event ID.
11. Confirm Sidekiq processes the delivery job.
12. Within 2 seconds (via auto-refresh), observe the webhook appearing in HookRe's **Recent Received Webhooks** list with a green **Verified** badge.
13. Click **View Detail →** and confirm:
    - **Verification Result**: Verified
    - **Webhook ID**: Matches HookYard delivery message ID
    - **Request ID**: Matches delivery attempt request ID
    - **Event Type**: `order.created` (read from payload `type` field)
    - **Captured Headers**: Includes `webhook-id`, `webhook-timestamp`, `webhook-signature`, `content-type` (`application/json`), and `user-agent` (`HookYard/1.0`).
    - **Raw Body**: Matches exact signed payload.
14. Inspect the HookYard database / console:
    - Confirm the `Message` is `succeeded`.
    - Confirm the `DeliveryAttempt` records HTTP 200, response body `{"received":true}`, response headers, execution duration, and `signing_secret_version: 1`.

### 4. Idempotency Verification
15. In HookRe, click **Send Event** again with the exact same idempotency key and same payload:
    - Confirm HookYard returns the previously accepted event without queuing duplicate delivery.
    - Confirm no second webhook arrives at HookRe.
16. In HookRe, change the payload (e.g. `"amount": 999999`) while keeping the same idempotency key:
    - Click **Send Event**.
    - Confirm HookYard returns HTTP 422 Unprocessable Entity (`Idempotency key reused with different payload`).

### 5. Failure Scenarios (Response Evidence)
17. In HookRe under **Receiver**, click **500 Error** or **503 Unavailable**.
18. Send a new event with a fresh idempotency key (`evt_test_002`):
    - Confirm HookRe receives the webhook, verifies the signature, marks it **Verified**, and returns HTTP 500/503.
    - Confirm HookYard marks the `Message` as `failed` and records one `DeliveryAttempt` with status 500/503 and response evidence.
    *(Note: Automatic retry belongs to Phase 6 and is not tested here.)*
19. In HookRe, click **200 (>4KB)** and send another event:
    - Confirm HookRe responds with HTTP 200 and a 5 KB+ response payload.
    - In HookYard, inspect the `DeliveryAttempt` response body and verify that HookYard truncates the recorded response body to its 4 KB limit.
20. Switch HookRe back to **200 OK**.

### 6. Signing-Secret Rotation
21. In HookYard, rotate the Endpoint's signing secret:
    - HookYard generates a new secret version (`v2`, `whsec_new...`) while keeping the old secret active for transition.
22. In HookRe, paste the new `whsec_new...` secret and click **Save Secret**.
23. Send an event from HookYard:
    - Confirm HookRe verifies the signature with the new secret and marks the webhook **Verified**.
    - Confirm HookYard's `DeliveryAttempt` records `signing_secret_version: 2`.
24. Verify rejection of retired secrets:
    - In HookYard, retire/remove the old secret.
    - In HookRe, temporarily enter an invalid or old secret:
    - Confirm HookRe rejects incoming webhooks with HTTP 401 Unauthorized and displays a red **Rejected** badge with reason `No matching signature found`.
    - Re-enter the active secret to restore normal delivery.

---

## Running Automated Tests

Run the full HookRe test suite:

```bash
bin/rails test
```

Run the signing-secret badge JavaScript unit tests:

```bash
node --test test/javascript/receiver_secret_badges.test.js
```
