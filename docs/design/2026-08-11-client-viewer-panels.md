# Client-Viewer Panels — Design Spec

**Date:** 2026-08-11
**Status:** Approved (Phase 0)
**Scope of this spec:** Phase 0 — Foundation & AI cleanup. Later phases are sketched in the Roadmap and each gets its own spec → plan → build cycle.

---

## 1. Vision

The right sidebar becomes a "swiss-army-knife" suite of **client-viewer tool panels** — database clients (Postgres/MySQL/SQLite), message queues (AMQP/RabbitMQ), object storage (S3), file transfer (FTP/SFTP), and an SSH client — living alongside the **already-shipping Docker and Processes panels**.

A client's *backend* (how it talks to its service) is decoupled from its *panel* (how it renders) behind a backend-agnostic **provider seam**, so a client can be CLI-backed, native-library-backed, or supplied by an **external plugin**. This lets the core app stay light: ship a few built-ins, and let plugins/CLIs fill in the long tail without touching the app.

## 2. Goals & Non-Goals (Phase 0)

**Goals**
- A generic, reusable **connection & credential model** in `SimpletonCore` that every future client panel shares.
- A reusable **panel-chrome scaffold** (`ClientPanelScaffold`) that removes the boilerplate every tool panel repeats.
- **Validate** the scaffold by retrofitting the existing **Docker** and **Processes** panels onto it (their first real consumers).
- **AI panel cleanup:** make the AI chat panel a special, header-only feature — no redundant activity-bar/sidebar entry — while preserving today's per-tab conversation behavior.
- CoreChecks coverage for the new model + store + credential store.

**Non-Goals (deliberately deferred)**
- No new client panel this phase (SQL is Phase 1).
- The backend **`ClientProvider` data seam is NOT built in Phase 0** — it is designed *with SQL* in Phase 1, its first real consumer. (Docker/Processes validate the *chrome*, not a data seam; their row models are unlike and must not be forced into one generic grid.)
- No external-plugin runtime this phase — it lands with the first plugin-based client.
- The existing SSH `Bookmark` / `BookmarkStore` / `KeychainManager` are **left untouched** (load-bearing). The new model is additive; SSH may migrate onto it later, out of scope here.

## 3. Roadmap

| Phase | Deliverable |
|------|-------------|
| **0 (this spec)** | Foundation: connection/credential model + `ClientPanelScaffold` + Docker/Processes retrofit + AI cleanup |
| 1 | **SQL** (Postgres/MySQL/SQLite) panel + the `ClientProvider` data seam (designed against SQL) |
| 2 | **S3** object-storage panel |
| 3 | **RabbitMQ / AMQP** panel (management HTTP API) |
| 4 | **FTP / SFTP** file-browser panel |
| 5 | **SSH client** panel |
| 6 | **External-plugin provider runtime** (the "stay light" path) |

Docker + Processes already exist and serve as reference implementations.

## 4. Existing Architecture (context the plan relies on)

- **Panel registry:** `Sources/Simpleton/Panels/PanelRegistry.swift` + `PanelDefinition.swift` (`id`, `name`, `icon`, `description`, `defaultSide`, `isBuiltIn`, `make: (PanelContext) -> NSViewController`). `PanelRegistry` lazily creates + caches one controller per id.
- **Profiles / rail:** `PanelProfile.swift` holds a single active panel per side (`leftActivePanelID` / `rightActivePanelID`) and hardcoded `defaultProfiles`. `ActivityBarView.swift` renders the right rail by iterating the active profile's panel-id list and matching `PanelRegistry.definitions` — **not a hardcoded list**.
- **Built-ins:** registered in `BuiltInPanels.swift` as static `PanelDefinition`s. Docker/Processes are built-ins (`isBuiltIn: true`), *not* plugins.
- **Panel pattern (Docker/Processes):** SwiftUI `View` wrapped by `NSHostingController`; blocking `Process` calls run off the main actor via `Task.detached`; `Timer`-based auto-refresh (5s / 3s) invalidated in `.onDisappear`; header (uppercase title + refresh) + `ThemedDivider` + `List(.plain)` + `PanelEmptyStateView`; `@ObservedObject themeSettings = ThemeSettings.shared`.
- **PanelContext:** dependency bag passed to `make` (e.g. `bookmarkStore`, `aiService`, `appConfig`, `currentPane`, `onInsertCommand`, `appSupportDir`).
- **Connections today (SSH-only):** `Sources/SimpletonCore/Models/Bookmark.swift` (SSH-centric: `AuthMethod` = `.key/.password/.agent/.none`, jump hosts, port forwards); `Sources/SimpletonCore/Core/BookmarkStore.swift` (actor, JSON at `…/Simpleton/bookmarks.json`, frecency); `Sources/Simpleton/KeychainManager.swift` (Keychain service hardcoded `com.simpleton.ssh`, account = bookmark UUID).
- **AI panel:** built-in panel `id: "ai-chat"`; per-tab `TabConversation` state; controller cached globally, conversation rebound on tab switch via `PanelRegistry.rebindAIChat(to:)`; toggled by the top-right header button (`.simpletonToggleAIChat` in `HeaderBarView.swift`).

## 5. Phase 0 Design

### Component 1 — Connection & credential model (`SimpletonCore`)

Generic, minimal, extensible; additive to (not a replacement for) the SSH `Bookmark` system.

**`Connection`** (`Sources/SimpletonCore/Models/Connection.swift`) — `Codable, Identifiable, Equatable`:
- `id: UUID`
- `name: String`
- `kind: ConnectionKind`
- `host: String?`
- `port: Int?`
- `username: String?`
- `params: [String: String]` — kind-specific fields (e.g. `database`, S3 `region`/`bucket`/`endpoint`, `useTLS`)
- `tags: [String]`, `pinned: Bool`
- `createdAt: Date`, `updatedAt: Date`

Tolerant decoding (per the project's `decodeIfPresent` convention) so future field additions never drop existing files.

**`ConnectionKind`** (enum, `String`-backed, `Codable, CaseIterable`): `.postgres`, `.mysql`, `.sqlite`, `.amqp`, `.s3`, `.ftp`, `.sftp` (+ `.ssh` reserved for a future SSH migration). Computed helpers: `defaultPort: Int?`, `icon: String` (SF Symbol), `displayName: String`, `requiresCredentials: Bool` (false for `.sqlite`).

**`ConnectionSecret`** (in `Connection.swift`) — `Codable, Equatable`: optional `password`, `accessKey`, `secretKey`, `token`, `passphrase`. Multi-field because e.g. S3 needs access key + secret key. Encoded as one JSON blob per connection.

**`ConnectionStore`** (`Sources/SimpletonCore/Core/ConnectionStore.swift`) — `actor`, mirrors `BookmarkStore`:
- JSON persistence to `…/Application Support/Simpleton/connections.json` (lazy-loaded).
- API: `add(_:)`, `update(_:)`, `delete(id:)`, `all()`, `byKind(_:)`, `pinned()`, `connection(for id:)`, `search(query:)`.
- Posts `.simpletonConnectionsChanged` after mutations (new `Notification.Name`).

**`CredentialStore`** (`Sources/SimpletonCore/Core/CredentialStore.swift`) — generalizes Keychain access beyond SSH's hardcoded service:
- Keychain service `com.simpleton.connection`, account = `connection.id.uuidString`.
- Stores/loads a `ConnectionSecret` encoded to JSON as the secret data; `kSecAttrAccessible = .whenUnlockedThisDeviceOnly`.
- API: `store(_ secret: ConnectionSecret, for id: UUID) -> Bool`, `secret(for id: UUID) -> ConnectionSecret?`, `delete(for id: UUID)`, `has(id: UUID) -> Bool`.
- Upsert logic (SecItemUpdate → fallback SecItemAdd) matching the robustness of the existing SSH `KeychainManager`. SSH's `KeychainManager` is left as-is.

### Component 2 — `ClientPanelScaffold` + Docker/Processes retrofit (`Simpleton/Panels`)

**`ClientPanelScaffold<Content: View>`** (`Sources/Simpleton/Panels/ClientPanelScaffold.swift`) — the shared chrome extracted from Docker/Processes:
- Renders: header (uppercase `title` + refresh button that shows a spinner while refreshing), `ThemedDivider`, then either the unavailable state or `content()`.
- Observes `ThemeSettings.shared` for live theming.
- Owns the auto-refresh `Timer` (interval = `autoRefresh`, `nil` = manual only), invalidated on `.onDisappear`; also refreshes on a manual tap.
- Inputs: `title: String`, `availability: ClientAvailability`, `autoRefresh: TimeInterval?`, `onRefresh: () async -> Void`, `@ViewBuilder content: () -> Content`.

**`ClientAvailability`** (in `ClientPanelScaffold.swift`) — enum:
- `.ready`
- `.unavailable(reason: String, action: <existing>?)` — the `action` reuses whatever the current `PanelEmptyStateView` already accepts for its optional action button (Docker's "Get Docker" / "Open Docker Desktop"); the scaffold passes it straight through rather than inventing a new type. The exact action type is bound during implementation from `PanelEmptyStateView`'s signature.

**Retrofit:**
- `DockerPanelView` and `ProcessesPanelView` wrap their existing row rendering in `ClientPanelScaffold`, deleting their now-duplicated header, `ThemedDivider`, timer, and empty-state code. Their bespoke row models and data-fetch logic are unchanged. Net: both files shrink; the scaffold is proven against two live consumers.

### Component 3 — AI panel → special/global (header-only, per-tab)

- Ensure `ai-chat` is **not enumerated in the activity-bar rail** and **not present in any default `PanelProfile` panel-id list**, so it never renders as a redundant rail/sidebar entry. (Exact current source of the redundant entry — a left Connections-sidebar shortcut vs. profile inclusion — is pinned during implementation and removed precisely.)
- The AI panel keeps its per-tab `TabConversation` + `rebindAIChat(to:)` behavior **unchanged**.
- AI remains opened **solely** by the top-right header button (`.simpletonToggleAIChat`), rendered into the right slot as a special panel outside the profile system.

## 6. Data Flow

- **Today (post-retrofit):** Docker/Processes `View` computes `availability` + rows from its `Process` calls (off main actor) → hands `availability`, `autoRefresh`, `onRefresh`, and its row `content` to `ClientPanelScaffold`, which paints chrome + drives the timer.
- **Future client (Phase 1+):** a client panel reads/writes its `Connection` via `ConnectionStore`, loads secrets via `CredentialStore`, connects through a (Phase-1) `ClientProvider`, and renders results inside `ClientPanelScaffold`. Phase 0 delivers everything except the provider.

## 7. Error Handling

- **Availability:** unavailable services (missing CLI, unreachable host — a client concern in later phases) surface through `ClientAvailability.unavailable` → `PanelEmptyStateView`, never a crash or blank panel.
- **Keychain:** `CredentialStore` returns `Bool`/optionals and surfaces failures to the caller (no silent success), matching how `AIKeychain`/`KeychainManager` handle ACL/ownership failures.
- **Persistence:** `ConnectionStore` tolerates a missing/corrupt `connections.json` by starting empty; tolerant decoding prevents field-addition data loss.

## 8. Testing (CoreChecks)

Add `Tests/CoreChecks/ConnectionChecks.swift`:
- `Connection` + `ConnectionSecret` Codable round-trip (including `params` and tolerant decode of a missing new field).
- `ConnectionKind` helpers (`defaultPort`, `requiresCredentials` for `.sqlite`).
- `ConnectionStore` CRUD + `byKind`/`search`/`pinned` + `.simpletonConnectionsChanged` fires on mutation (temp support dir, as with existing store checks).
- `CredentialStore` store/retrieve/delete/has round-trip, guarded the same way the existing Keychain-dependent checks are (skipped when Keychain is unavailable in the runner).

`ClientPanelScaffold` and the AI cleanup are UI — covered by the build and the existing headless e2e; no new headless UI assertions.

## 9. File Structure (Phase 0)

**Create**
- `Sources/SimpletonCore/Models/Connection.swift` — `Connection`, `ConnectionKind`, `ConnectionSecret`
- `Sources/SimpletonCore/Core/ConnectionStore.swift` — `ConnectionStore` actor
- `Sources/SimpletonCore/Core/CredentialStore.swift` — `CredentialStore`
- `Sources/Simpleton/Panels/ClientPanelScaffold.swift` — `ClientPanelScaffold`, `ClientAvailability` (reusing `PanelEmptyStateView`'s existing action type)
- `Tests/CoreChecks/ConnectionChecks.swift`

**Modify**
- `Sources/Simpleton/Panels/DockerPanelView.swift` — wrap in scaffold, delete duplicated chrome
- `Sources/Simpleton/Panels/ProcessesPanelView.swift` — wrap in scaffold, delete duplicated chrome
- `Sources/Simpleton/Panels/PanelProfile.swift` and/or `ActivityBarView.swift` — exclude `ai-chat` from rail/default-profile enumeration
- `Sources/SimpletonCore/…/Notifications` (wherever `Notification.Name` extensions live) — add `.simpletonConnectionsChanged`
- `Tests/CoreChecks/` runner registration — include `ConnectionChecks`

**Untouched (explicitly):** `Bookmark.swift`, `BookmarkStore.swift`, `KeychainManager.swift`, AI conversation/rebind logic.

## 10. Resolved Decisions

- **Backend:** not a single choice — a backend-agnostic **provider seam** is the direction (CLI + native + plugin all coexist). Phase 0 ships the connection substrate + chrome; the provider seam is designed with SQL (Phase 1); the plugin runtime with the first plugin client.
- **Slice:** pure foundation + AI cleanup this phase; no new client.
- **Validation:** retrofit Docker + Processes onto the scaffold.
- **AI:** header-only, per-tab (today's behavior), just de-duplicated from the rail.
- **Connection/credential model:** included in Phase 0 (shared substrate, low-risk, fully unit-tested), kept minimal + extensible so Phase 1 can firm up fields without churn.
- **SSH:** existing Bookmark system untouched; new model is additive.
