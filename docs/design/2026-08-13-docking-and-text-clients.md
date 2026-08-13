# Docking & Launcher + Text Clients — Design Spec

**Date:** 2026-08-13
**Status:** Approved (design locked in prior conversation; this formalizes it)
**Part of:** the "Client Workbench" redesign — **sub-project 2 of 2**. Sub-project 1 (Connection Manager) is built.
**Builds on:** the SQL client + Connection Manager (branch `feature/client-workbench`).

Two separately-buildable phases:
- **2a — Docking + launcher + shared-registry fix** (the layout foundation; highest risk).
- **2b — Text-client CLI panes** (drag a connection into the shells → a terminal pane running its CLI).

---

## 1. Locked Model (recap)

- The right 40px activity rail becomes a **tool-panel launcher**, **hideable in Preferences**. The AI chat remains the right *panel*.
- **Click a Data Connections row → GUI client** (the native SwiftUI SQL panel) opens in a **resizable, edge-dockable drawer** — **bottom** by default, movable to **top/right**, drag-resized. The drawer is a **new dock slot**, NOT a leaf in the terminal split tree.
- **Drag a Data Connections row into the shells → text client**: a real terminal **pane** running the connection's CLI, via the existing pane-factory pattern. Split tree untouched.
- Both actions come from the same `Connection` + `CredentialStore` (sub-project 1). This realizes the "one connection → click=GUI, drag=text" model.

## 2. Current Architecture (verified)

- `TabContainerController.contentSplit`: a **flat horizontal 3-slot** `NSSplitView` — `[leftPanel?] | terminalSplit | [rightPanel?]` — between two 40px `ActivityBarView` rails (`mountActivityBars`). `updatePanels(for:)` inserts/removes the left/right panel VCs as arranged subviews and sets divider positions.
- `PanelRegistry` (single, app-wide): `@Published activeProfile`, a **shared controller cache** `controllers[id]` (one instance per panel id, reused across all windows/tabs), `makeController(for:context:)`, `register(_:)`. `PanelProfile` is `Codable, Identifiable` — **not `Equatable`**; the `subscribeToRegistry()` sink has **no `.removeDuplicates()`**, so every `activeProfile` assignment rebuilds panels in **every** container.
- `ActivityBarView`: renders `activeProfile.{left,right}PanelIDs`; each icon `.onDrag { NSItemProvider(object: panelID as NSString) }`; a rail-level `.onDrop` moves panels between sides.
- `SplitController`: a tree of terminal `PaneController`s; `splitFocusedPane(direction:)` uses an injected `paneFactory`. `openSSHConnection` and `openCommandPane` **already** swap the factory to spawn a specialized pane, then restore it.
- `PaneController`: `ConnectionType` = `.local(shell:workingDirectory:)` | `.ssh(bookmarkID:)`; `startSSH(bookmark:config:)` builds `command.{executable,arguments,environment}` and calls `terminalView.startProcess(executable:args:environment:…)`. This is the template for a client pane.
- `TerminalDropTarget`: an overlay accepting **`.fileURL`** drops only (sends quoted paths to the shell); `hitTest` returns nil so mouse events pass through.
- `AppearanceConfig` (tolerant Codable, in `SimpletonCore`): holds bools/doubles like `chromeTranslucency`, toggled in `PreferencesWindow` via `$config.appearance.<field>` + `onChanged(config)`.

## 3. CLI availability (measured on this machine)

`psql`, `mysql`, `sqlite3` are installed; the nicer TUIs `pgcli`/`mycli`/`litecli` are **not**. So the text client must **detect + fall back** per kind and degrade gracefully when nothing is found (like the Docker panel's "not installed" state).

---

## Phase 2a — Docking, launcher, shared-registry fix

### 2a.1 `PanelProfile`: drawer slot + `Equatable`

Add to `PanelProfile`:
```swift
var bottomActivePanelID: String?   // the GUI client panel docked in the drawer (nil = closed)
var drawerEdge: DockEdge = .bottom // .bottom | .top | .trailing
var drawerSize: CGFloat = 260      // height when top/bottom; width when trailing
```
Add `enum DockEdge: String, Codable { case bottom, top, trailing }` and make **`PanelProfile: Equatable`** (all members are Equatable). Add mutation helpers `setDrawer(id:on:)` / `closeDrawer()`. Persisted via the existing `profiles.json` (Codable already tolerant of new keys since it decodes whole profiles; add defaults). The drawer hosts exactly one GUI panel at a time (single-drawer model, matching the single-active-per-side model).

### 2a.2 Registry multi-window fix (the highest-risk change)

**Problem:** one shared `controllers[id]` instance + one shared `activeProfile` means an `activeProfile` change rebuilds panels in every `TabContainerController`, each re-parenting the *same* cached NSView — so a panel can only live in one window at a time and reveal-targeting is nondeterministic.

**Fix (two parts):**
1. **Per-container controller cache.** Move the panel-controller cache off the singleton `PanelRegistry` and onto each `TabContainerController` (each keeps its own `[panelID: NSViewController]`, built from `PanelDefinition.make` via the registry's *definitions*). `PanelRegistry` keeps `definitions` + `activeProfile` + profile management, but no longer owns live controllers. `rebindAIChat` moves to per-container rebinding of that container's cached AI controller. Result: each window/tab independently instantiates and shows its panels; no cross-window NSView tug-of-war.
2. **`.removeDuplicates()` on the sink.** With `PanelProfile: Equatable`, add `.removeDuplicates()` to the `registry.$activeProfile` sink so a no-op profile assignment doesn't rebuild. Keep the sub-project-1 reveal early-return.

*Scope note:* this is an app-wide change touching every panel. It is required by the locked design ("resolve the shared-registry multi-window issue") and is the single riskiest item; it gets its own tasks + careful verification (all existing panels still mount/switch; AI rebinding still works; e2e still passes).

### 2a.3 `contentSplit` restructure → bottom drawer

Wrap the current horizontal 3-slot split in an **outer `NSSplitView`** whose orientation depends on `drawerEdge`:
- `.bottom`/`.top`: outer split is **horizontal-divider** (vertical stack); slots = `[innerHorizontalSplit, drawerHost]` (drawer below for `.bottom`, above for `.top`).
- `.trailing`: the drawer is a fourth arranged subview appended to the inner horizontal split (to the right of the right rail), OR the outer split is vertical-divider with `[inner, drawer]`. For v1 we implement `.bottom` fully and `.top`/`.trailing` as the same mechanism with the edge parameter; if `.trailing` complicates the rail geometry, ship `.bottom`/`.top` first and treat `.trailing` as a fast-follow (flagged, not silently dropped).

`updatePanels(for:)` gains a step that mounts/uninstalls the drawer host from `bottomActivePanelID` and sets the outer divider from `drawerSize`. The drawer host reuses the per-container controller cache (2a.2), so the SQL panel instance is the *same* whether shown in the drawer or (legacy) a side slot. Dragging the outer divider resizes; persist `drawerSize` back to the profile on divider change (debounced).

### 2a.4 Launcher rail (hideable)

- Add `AppearanceConfig.showToolLauncher: Bool = true` (tolerant-decoded) + a `PreferencesWindow` toggle ("Show tool launcher rail") in the Window section, mirroring `thinStrokes`.
- The **right** `ActivityBarView` becomes the launcher: it renders the launcher panel ids, and `updateRightBarVisibility` also hides it when `showToolLauncher == false`. Clicking a launcher icon whose panel is a **GUI client** (declared via a new `PanelDefinition.prefersDrawer: Bool`) sets `bottomActivePanelID` (opens the drawer) instead of the right side; other panels keep today's toggle behavior. The SQL panel sets `prefersDrawer = true` and its default placement moves from `rightPanelIDs:["sql"]` to the **drawer** (Developer profile: `bottomActivePanelID: nil`, SQL launched on demand).

### 2a.5 SQL fold-in

The built SQL panel's `.gui` reveal (sub-project 1) now targets the **drawer**: the reveal observer sets `bottomActivePanelID = .sql` (via a new `activateDrawer(id:)`), and `SQLPendingOpen` consumption is unchanged. Remove SQL from `rightPanelIDs` defaults. The SQL panel view is unchanged (it renders identically in the drawer host).

### 2a.6 Testing

CoreChecks: `PanelProfile` Equatable + drawer-field Codable round-trip + tolerant decode; `DockEdge` Codable; `setDrawer`/`closeDrawer` mutation helpers. UI (drawer geometry, launcher hide, per-container cache) verified by build + the headless e2e (must stay `SIMP-WSE2E RESULT PASS`) + manual.

---

## Phase 2b — Text-client CLI panes

### 2b.1 `ConnectionType.client` + `startClient`

Add `case client(connectionID: UUID)` to `ConnectionType` (`SimpletonCore/PaneState.swift`; it's `Equatable`). Add `PaneController.startClient(connection:secret:)`:
- Resolve the CLI for `connection.kind` with a fallback chain, checking each on disk (like `findDocker`): postgres → `pgcli` else `psql`; mysql → `mycli` else `mysql`; sqlite → `litecli` else `sqlite3`. If none found → `bannerManager?.showError("Install psql/mysql/sqlite3 to open a text client")` and return.
- Build args + **environment** so no secret hits argv or shell history: postgres `psql` → args `["-h",host,"-p",port,"-U",user,"-d",db]`, env `["PGPASSWORD=<secret>"]`; mysql `mysql` → args `["-h",host,"-P",port,"-u",user,db]`, env `["MYSQL_PWD=<secret>"]`; sqlite `sqlite3` → args `[path]`, no env. (TUI variants take the same connection args; pgcli/mycli also honor `PGPASSWORD`/`MYSQL_PWD`.)
- `connectionType = .client(connection.id)`; `terminalView.terminate()` then `startProcess(executable:args:environment:)` — mirroring `startSSH`.

### 2b.2 `openClientPane`

Add `TabContainerController.openClientPane(connection:secret:direction:)` mirroring `openSSHConnection`: swap `paneFactory` to build a pane then `startClient(connection:secret:)`, `splitFocusedPane(direction:)`, restore the factory, refocus. Secret is fetched once via `CredentialStore.secret(for: connection.id)` at the call site.

### 2b.3 Drag a connection → drop on the terminal

- The Data Connections row's drag payload is the **connection id** on a dedicated UTType (`"com.simpleton.connection-id"`), distinct from the panel-id `.plainText` used by the rail, so terminal drops and rail drops never cross-fire.
- Extend the terminal drop surface to accept that UTType: register it on `TerminalDropTarget` (add the type; keep `.fileURL`), and on a connection-id drop call `openClientPane(connection:secret:direction:.vertical)` for the pane under the drop (default: split the focused pane). File-URL behavior is unchanged.
- `DataConnectionRow` gains `.onDrag` producing an `NSItemProvider` for the connection-id type. Only SQL kinds today (sub-project 1 already gates non-SQL); a future S3/etc. client would extend `startClient`.

### 2b.4 Testing

CoreChecks: the CLI-resolution + arg/env builder is pure logic — unit-test it (given a `Connection` of each kind, assert the chosen executable candidates + args + env keys, with the password in env not args). Actual process spawning is manual/e2e. Guard the "which binary exists" probe like the Docker/Keychain checks (skip if none installed).

---

## 4. Error Handling

- No CLI installed → banner + no pane spawned (2b). Drawer with no panel → collapsed (2a). Missing credentials → the CLI prompts (its normal behavior); we never block. Malformed profile (bad `drawerEdge`) → tolerant decode falls back to `.bottom`.
- The registry refactor must preserve every existing panel's mount/switch and AI rebinding; regression caught by build + e2e + manual profile switching.

## 5. File Structure

**Phase 2a — Modify:** `SimpletonCore/Models/AppConfig.swift` (`showToolLauncher`); `Panels/PanelProfile.swift` (drawer fields, `DockEdge`, `Equatable`, helpers, default profiles); `Panels/PanelRegistry.swift` (drop the controller cache; keep definitions/profiles) → **Create** per-container cache in `TabContainerController.swift` (+ `contentSplit` outer-split restructure, drawer mount, launcher-hide, reveal→drawer); `Panels/ActivityBarView.swift` (launcher click → drawer for `prefersDrawer` panels); `Panels/PanelDefinition.swift` (`prefersDrawer`); `Panels/BuiltInPanels.swift` (SQL `prefersDrawer: true`); `Views/PreferencesWindow.swift` (toggle); `Tests/CoreChecks/…` (profile checks).
**Phase 2b — Modify:** `SimpletonCore/Models/PaneState.swift` (`.client`); `PaneController.swift` (`startClient`); `TabContainerController.swift` (`openClientPane` + drop handling); `TerminalDropTarget.swift` (accept connection-id type); `Panels/Connections/DataConnectionRow.swift` (`.onDrag`). **Create:** `SimpletonSQL` or `Simpleton` `SQLClientCommand.swift` (pure CLI-resolution + arg/env builder) + `Tests/CoreChecks/SQLClientCommandChecks.swift`.

## 6. Resolved Decisions

- Two phases: **2a docking/launcher/registry-fix**, then **2b text clients** (independent; 2a first).
- GUI client docks in a **bottom edge-dockable drawer** (new slot); **not** a split-tree leaf.
- Text client = a **terminal pane** running the CLI via the existing factory-swap; **creds via env**, never argv/shell-history; split tree untouched.
- Text-client drag source = a **Data Connections row** (per-connection), on a dedicated connection-id UTType.
- **Registry multi-window fix = per-container controller cache + `PanelProfile: Equatable` + `.removeDuplicates()`** — required, highest-risk, isolated to its own tasks.
- `.bottom`/`.top` drawer edges ship first; `.trailing` is a flagged fast-follow if rail geometry complicates it.
- CLI fallback chain pgcli→psql / mycli→mysql / litecli→sqlite3, graceful "not installed".
