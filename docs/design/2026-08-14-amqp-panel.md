# AMQP (RabbitMQ) management panel

Date: 2026-08-14
Status: implemented

## Goal

Add a GUI client panel for inspecting and lightly operating a RabbitMQ broker, mirroring the
existing SQL client (`SimpletonSQL` + SQL panel). It surfaces queues, exchanges, connections and
channels, and supports peeking messages, publishing, and purging a queue.

## Backend decision

Use the **RabbitMQ Management HTTP API** over Foundation `URLSession`. This is the management
plane RabbitMQ already exposes on port `15672` (`15671` for TLS) and needs **no third-party
dependency** and no AMQP protocol client. JSON over `http(s)://host:port/api` with HTTP Basic Auth.

This is a management/observability panel, not a message-bus client — so the HTTP management API is
the correct, dependency-free seam. Publishing and peeking through the management API is officially
supported (and clearly documented as unsuitable for high throughput, which matches a GUI's use).

## Architecture

New SPM library target **`SimpletonAMQP`** (deps: `["SimpletonCore"]` only), isolating the client
from the app the same way `SimpletonSQL` does.

- `AMQPManagementBackend` — the protocol seam (mirrors `SQLDriver`). All I/O is async, off the main
  actor, and every failure is mapped to `AMQPError` so no raw URLSession error escapes.
- Pure `Sendable`/`Codable` model: `Overview`, `QueueInfo`, `ExchangeInfo`, `ConnectionInfo`,
  `ChannelInfo`, `MessagePreview`. Custom `CodingKeys` map the management API's snake_case JSON.
- `RabbitMQManagementDriver` — the concrete backend. Builds requests with an
  `Authorization: Basic base64(user:password)` header; strict percent-encoding of vhost + resource
  names in the path (default vhost `/` → `%2F`); TLS toggle via `params["useTLS"]` with an optional
  allow-self-signed via a `URLSessionDelegate`.
- `AMQPBackendFactory.make(_:secret:)` — switches on `ConnectionKind`; `.amqp` → driver, everything
  else throws `.unsupported`.

### Endpoints

| Operation    | Method | Path                                          | Body |
|--------------|--------|-----------------------------------------------|------|
| overview     | GET    | `/api/overview`                               | —    |
| queues       | GET    | `/api/queues/{vhost}`                         | —    |
| exchanges    | GET    | `/api/exchanges/{vhost}`                      | —    |
| connections  | GET    | `/api/connections`                            | —    |
| channels     | GET    | `/api/channels`                               | —    |
| get messages | POST   | `/api/queues/{vhost}/{queue}/get`             | `{"count":N,"ackmode":"ack_requeue_true","encoding":"auto","truncate":50000}` |
| publish      | POST   | `/api/exchanges/{vhost}/{exchange}/publish`   | `{"properties":{},"routing_key":"…","payload":"…","payload_encoding":"string"}` |
| purge        | DELETE | `/api/queues/{vhost}/{queue}/contents`        | —    |

`getMessages` uses `ackmode: ack_requeue_true` so peeking is non-destructive (messages are
requeued). `payload_encoding: base64` responses are decoded to text where possible.

### Error mapping

`AMQPError`: `401/403 → .auth`, `404 → .notFound`, non-2xx → `.requestFailed(status,body)`,
transport/DNS/TLS failures → `.connectionFailed`, decode failures → `.decodeFailed`,
non-`.amqp` kind → `.unsupported`.

## Panel (GUI, drawer)

`AMQPPanelView` + `AMQPPanelModel`, mirroring the SQL panel:

- Connection Picker filtering `ConnectionKind.amqp`; connect on selection change.
- `ClientPanelScaffold(title:"AMQP", autoRefresh: 5, …)` for shared chrome + gentle auto-refresh.
- A segmented view over **Queues / Exchanges / Connections / Channels** tables.
- Row actions on a queue: **Get messages** (peek preview sheet), **Publish** (exchange/routing
  key/payload sheet), **Purge** (confirmation).
- `themedGlass(DT.surface)` + theme tokens; pending-open consumed via
  `PendingClientOpen.shared.take(for: PanelProfile.PanelID.amqp)`.

Registration: `PanelProfile.PanelID.amqp`, `PanelDefinition.amqp` (`prefersDrawer: true`),
`panelRegistry.register(.amqp)`, and
`GUIClientRegistry.shared.register(kinds: [.amqp], panelID: .amqp)`.

`DataConnectionEditor` gains `.amqp`: Name, Host, Port (default 15672), Vhost (default `/`), User,
Password (SecureField), Use TLS. Non-secret config → `Connection` + `params["vhost"]`/`["useTLS"]`;
password → `ConnectionSecret.password` in the Keychain.

## MVP scope

In: the six read tables + get-messages/publish/purge, TLS toggle, auto-refresh, editor fields,
headless CoreChecks. Out (later): message TTL/DLX editing, queue/exchange creation, bindings graph,
per-node metrics history.

## Verification

- `swift build` — compiles clean.
- `swift run CoreChecks` — pure checks for percent-encoding (`/` → `%2F`), Basic-auth header,
  Codable decode of sample management JSON, base64 payload decode, error mapping, and factory
  mapping. Env-gated live check hits `/api/overview` when `SIMPLETON_AMQP_TEST_URL` (+ `_USER`,
  `_PASSWORD`) are set, else prints "skipped".
- `swift format lint --strict` — clean.
</content>
</invoke>
