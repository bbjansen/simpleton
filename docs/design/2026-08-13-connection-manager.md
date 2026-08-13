# Connection Manager — Design Spec

**Date:** 2026-08-13
**Status:** Approved
**Part of:** the "Client Workbench" redesign (sub-project 1 of 2). Sub-project 2 = Docking & launcher + SQL fold-in (own spec).
**Builds on:** Phase 0 foundation (`Connection`/`ConnectionKind`/`ConnectionSecret`, `ConnectionStore`, `CredentialStore`) + the SQL client (`feature/sql-viewer`, folded in via the branch).
**Research:** connection-model research (two agents; DB clients + multi-protocol managers) concluded: one record + `kind` discriminator, reusable tunnel-reference, groups + per-connection color, one-entry-multiple-actions. Unify-vs-parallel resolved as **parallel now, convergeable later**.

---

## 1. Goal & Scope

A bookmark/manager for **data connections** (Postgres/MySQL/SQLite now; S3/RabbitMQ/FTP later), mirroring the existing SSH connections sidebar (`SidebarView`). It is what both the GUI and (later) text clients launch *from*.

**In scope**
- Model additions to `Connection`: `color`, `group`, `tunnelBookmarkID` (all optional, backward-compatible).
- `ConnectionStore` query additions: `groups()`, `byGroup(_:)`.
- A **"Data Connections"** management panel: grouped list (color dot + kind icon + name + tags), search, pin/delete/duplicate, "＋ Add Connection", and an add/edit sheet (kind, host/port/user/password/database, **color picker, group, tags, tunnel-through-SSH-bookmark picker**).
- A **launch-action seam** (`ConnectionLaunch { .gui, .text }`); `.gui` wired to open the built SQL panel focused on the selected connection.

**Non-goals (→ sub-project 2)**
- Launcher rail (hideable), bottom edge-dockable GUI drawer, drag→text-client CLI panes.
- Unifying the SSH `Bookmark` system into `Connection` (`.ssh` stays reserved in `ConnectionKind` for a later migration).
- Nested (multi-level) groups; inline tunnels (v1 is single-level groups + tunnel-by-reference).

## 2. Data-Model Additions (`SimpletonCore`)

`Sources/SimpletonCore/Models/Connection.swift` — add to `Connection` (all optional; tolerant `decodeIfPresent` so older `connections.json` still loads):

```swift
/// Env-safety accent, reusing the app's accent names: red/orange/yellow/green/blue/purple/pink/graphite.
/// Convention: prod = red. The client chrome tints by this. Nil = no color.
public var color: String?
/// Single-level group name (e.g. "prod", "staging"). Nil = ungrouped. Nested groups are a later enhancement;
/// `tags` provides the cross-cutting axis meanwhile.
public var group: String?
/// References an existing SSH `Bookmark` (by its UUID) to tunnel this connection through a bastion.
/// Nil = direct connection. No inline tunnel in v1 (avoids duplicating SSH host config).
public var tunnelBookmarkID: UUID?
```

Add to the memberwise `init` (defaults `nil`) and to the tolerant `init(from:)` via `decodeIfPresent`. Secrets stay in `CredentialStore` (unchanged). No change to `ConnectionKind`.

## 3. Store Additions (`ConnectionStore`)

`Sources/SimpletonCore/Core/ConnectionStore.swift` — add:
```swift
/// Distinct non-nil group names, sorted.
public func groups() -> [String]
/// Connections in a given group, sorted by name.
public func byGroup(_ group: String) -> [Connection]
```
Existing `add/update/delete/all/byKind/pinned/connection(for:)/search/flush` + `.simpletonConnectionsChanged` are unchanged; the new fields persist automatically.

## 4. Management UI (`Simpleton` app)

New `Sources/Simpleton/Panels/Connections/DataConnectionsPanel.swift` (+ small subviews), a SwiftUI panel mirroring `SidebarView`'s structure:
- **Sections**: **Pinned**, then **one section per group** (group name header, sorted), then **Ungrouped**. Reuse the existing `SidebarSectionHeader` style. (No "Recent" section — `Connection` has no frecency, unlike SSH `Bookmark`.)
- **Row** (`DataConnectionRow`): a leading **color dot** (from `color`, else neutral), the **kind icon** (`ConnectionKind.icon`), the **name**, and **tag chips**. Row tap → `.gui` launch (§5). Context menu: Pin/Unpin, Edit, Duplicate, Delete, plus "Open as text client" (stub → sub-project 2).
- **Search** field filters via `ConnectionStore.search`.
- **"＋ Add Connection"** ghost button pinned at the bottom (mirrors `SidebarView`).
- Refresh on `.simpletonConnectionsChanged` (as `SidebarView` does for bookmarks).

**Add/Edit sheet** `DataConnectionEditor.swift` (extends the SQL connection editor): kind picker → conditional fields (SQLite path; server host/port/user/password/database + TLS); **color picker** (the 8 accent swatches + "none"); **group** field (free text with existing-groups autocomplete from `groups()`); **tag editor**; **"Tunnel through…"** picker listing SSH `Bookmark`s (from the injected `BookmarkStore`) → sets `tunnelBookmarkID`. Save writes the `Connection` via `ConnectionStore` and the password via `CredentialStore` (as the SQL editor already does).

**Registration**: a built-in panel `data-connections` (icon e.g. `cylinder.split.1x2` or `bookmark`), `defaultSide: .left`, registered in `BuiltInPanels` + `AppDelegate` + `PanelProfile.PanelID.dataConnections`. Placement into the launcher is refined in sub-project 2. The panel's `make` closure pulls `context.appSupportDir` (for `ConnectionStore`) and `context.bookmarkStore` (for the tunnel picker).

## 5. Launch-Action Seam

```swift
public enum ConnectionLaunch: Sendable { case gui, text }
```
The panel takes an `onLaunch: (Connection, ConnectionLaunch) -> Void` callback. Sub-project 1 wires **`.gui`** in `BuiltInPanels`/`TabContainerController` to reveal the SQL panel and select that connection (a notification, e.g. `.simpletonOpenConnectionGUI`, observed by the SQL panel model to pick the connection + connect). **`.text`** posts a stub notification logged for now; sub-project 2 implements the CLI pane. This is the concrete entry point for the "one connection → multiple actions" model (click = GUI, drag = text).

## 6. Security & Credentials

- Passwords/secrets remain in `CredentialStore` (Keychain, `com.simpleton.connection`), keyed by `connection.id`; only non-secret metadata in `connections.json`.
- The tunnel is a **reference** (`tunnelBookmarkID`) — no SSH secret is copied; the SSH `Bookmark`'s own credential (via the SSH `KeychainManager`) stays its own. Actual tunnel *establishment* is sub-project 2 (text client) / future GUI-over-tunnel; v1 only stores the reference.
- No credentials on any command line (relevant in sub-project 2; noted here for continuity).

## 7. Testing (CoreChecks)

`Tests/CoreChecks/ConnectionChecks.swift` (extend) / `ConnectionManagerChecks.swift`:
- `Connection` round-trip incl. `color`/`group`/`tunnelBookmarkID`; **tolerant decode** of a legacy JSON record missing all three → fields default `nil`, no failure.
- `ConnectionStore.groups()` returns distinct sorted names; `byGroup(_:)` filters correctly; new fields persist across store instances.
- Existing `Connection`/`ConnectionStore`/`CredentialStore` checks stay green.
UI (panel, editor, launch seam) verified by `swift build` + manual; no headless UI assertions.

## 8. File Structure

**Modify**
- `Sources/SimpletonCore/Models/Connection.swift` — add `color`/`group`/`tunnelBookmarkID` (+ init + tolerant decode).
- `Sources/SimpletonCore/Core/ConnectionStore.swift` — add `groups()`/`byGroup(_:)`.
- `Sources/Simpleton/Panels/BuiltInPanels.swift` — register `dataConnections`.
- `Sources/Simpleton/Panels/PanelProfile.swift` — add `PanelID.dataConnections`; include in a default profile (left).
- `Sources/Simpleton/AppDelegate.swift` — `panelRegistry.register(.dataConnections)`; wire the `.gui` launch notification.
- `Tests/CoreChecks/ConnectionChecks.swift` + `main.swift` — new checks.

**Create**
- `Sources/Simpleton/Panels/Connections/DataConnectionsPanel.swift` — the panel view + model.
- `Sources/Simpleton/Panels/Connections/DataConnectionRow.swift` — the row.
- `Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift` — add/edit sheet.

## 9. Resolved Decisions

- **Parallel now, convergeable later** — data connections on the `Connection` model; SSH `Bookmark` untouched; `.ssh` reserved for later unification.
- **Tunnel = reference to an SSH bookmark** (`tunnelBookmarkID`); no inline tunnel in v1.
- **Single-level `group`** (string) for v1; nested folders deferred; `tags` cover cross-cutting now.
- **Color = the app's 8 accent names**, prod=red convention, tints client chrome.
- **Launch seam** defined here; `.gui` wired to the SQL panel; `.text` (CLI pane) is sub-project 2.
- Manager registered as a normal left panel now; launcher placement is sub-project 2.
