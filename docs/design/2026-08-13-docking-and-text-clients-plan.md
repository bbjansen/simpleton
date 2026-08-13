# Docking + Launcher + Text Clients — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an edge-dockable GUI drawer + hideable tool-launcher rail, and let a Data Connection be dragged into the terminal to open a text (CLI) client pane.

**Architecture:** `PanelProfile` gains a drawer slot + `Equatable`; `TabContainerController.contentSplit` is wrapped in an outer split hosting a bottom drawer; the SQL panel docks there. Text clients reuse the SSH pane-factory pattern (`startClient` mirrors `startSSH`, creds via env). The shared panel-controller cache moves per-container (multi-window fix), done last and isolated.

**Tech Stack:** Swift 6 / SPM (no Xcode), AppKit + SwiftUI-in-`NSHostingView`, SwiftTerm, `CoreChecks` runner.

**Spec:** `docs/design/2026-08-13-docking-and-text-clients.md`

## Global Constraints

- Build `swift build`; check `swift run CoreChecks`; lint `swift format lint --recursive --parallel --strict Sources Tests` (exit 0; auto-fix with `swift format --in-place --recursive Sources Tests`).
- Codable stays **tolerant** (`decodeIfPresent`, missing keys → defaults).
- SSH `Bookmark`/`BookmarkStore`/`KeychainManager` **untouched**; secrets stay in `CredentialStore`; CLIs receive passwords via **environment** (`PGPASSWORD`/`MYSQL_PWD`), never argv or shell history.
- Every task ends with build + CoreChecks + lint green and the **headless e2e** staying `SIMP-WSE2E RESULT PASS` (`bash scripts/e2e/workspace-e2e.sh`).
- Conventional commits, **no co-author, no Claude/AI mention**.
- **Order = low-risk first.** Group E (per-container registry refactor) is highest-risk, last, isolated; **if it destabilizes existing panels, STOP and flag** rather than force.

## Integration facts (verified verbatim)

- `PanelProfile` (`Sources/Simpleton/Panels/PanelProfile.swift`): `struct PanelProfile: Codable, Identifiable` with `id,name,leftPanelIDs,rightPanelIDs,leftActivePanelID,rightActivePanelID,leftWidth=240,rightWidth=320`; synthesized Codable; helpers `togglePanel/movePanel/activatePanel`; `enum PanelID`; `defaultProfiles` (General/Developer/DevOps; Developer `rightPanelIDs:["sql"]`).
- `PanelRegistry` (`.../PanelRegistry.swift`): `@Published activeProfile`; `controllers[id]` cache; `makeController(for:context:)`; `register`; `rebindAIChat(to:)`; `evictController(for:)`.
- `TabContainerController` (`Sources/Simpleton/TabContainerController.swift`): `contentSplit: NSSplitView?` (vertical=true → horizontal dividers? — it's `isVertical=true`, left↔right); created in `loadView` (`split.isVertical=true`, `split.addArrangedSubview(splitController.rootView)`); `mountActivityBars(in:registry:)` pins `[leftBar(40) | split | rightBar(40)]`; `updatePanels(for:)` inserts left VC at index 0 / right VC at end + sets divider positions; `subscribeToRegistry()` sinks `registry.$activeProfile` → `updatePanels` (no `.removeDuplicates()`); `updateRightBarVisibility(for:)` collapses right rail to 0 when `rightPanelIDs.isEmpty`; `openSSHConnection`/`openCommandPane` swap `splitController.paneFactory` then `splitFocusedPane`.
- `ActivityBarView` (`.../ActivityBarView.swift`): renders `activeProfile.{side}PanelIDs`, `.onDrag { NSItemProvider(object: panelID as NSString) }`, rail `.onDrop(of:[.plainText])`→`movePanel`; `togglePanel(id:)` mutates `activeProfile`.
- `ConnectionType` (`Sources/SimpletonCore/Models/PaneState.swift`): `enum ConnectionType: Equatable { case local(shell:workingDirectory:); case ssh(bookmarkID:) }`.
- `PaneController` (`Sources/Simpleton/PaneController.swift`): `startSSH(bookmark:config:)` builds `command.{executable,arguments,environment}`, `terminalView.terminate()` then `terminalView.startProcess(executable:args:environment:execName:currentDirectory:)`; `bannerManager?.showError(message:)`; `TerminalDropTarget(terminal:)` added as subview.
- `TerminalDropTarget` (`Sources/Simpleton/TerminalDropTarget.swift`): `registerForDraggedTypes([.fileURL])`; `performDragOperation` sends quoted paths.
- `AppearanceConfig` (`Sources/SimpletonCore/Models/AppConfig.swift`): tolerant Codable with `chromeTranslucency`/`thinStrokes`; `PreferencesWindow.swift` toggles via `$config.appearance.<field>` + `onChanged(config)` in the "Window" section.
- `DataConnectionRow` (`Sources/Simpleton/Panels/Connections/DataConnectionRow.swift`): `Button(action: onTap)`; `SQLPanelModel.sqlKinds = [.sqlite,.postgres,.mysql]`.

---

## File Structure

**Group A** — Modify `PanelProfile.swift` (Equatable, `DockEdge`, drawer fields, tolerant init, helpers), `TabContainerController.swift` (`.removeDuplicates()`), `Tests/CoreChecks/` (+ `PanelProfileChecks.swift`, register in `main.swift`).
**Group B** — Create `Sources/SimpletonSQL/SQLClientCommand.swift`, `Tests/CoreChecks/SQLClientCommandChecks.swift`; modify `PaneState.swift` (`.client`), `PaneController.swift` (`startClient`, executable resolver), `TabContainerController.swift` (`openClientPane` + text-drop observer), `TerminalDropTarget.swift` (accept connection-id type), `DataConnectionRow.swift` (`.onDrag`).
**Group C** — Modify `AppConfig.swift` (`showToolLauncher`), `PreferencesWindow.swift` (toggle), `TabContainerController.swift` (`updateRightBarVisibility`), `PanelDefinition.swift` (`prefersDrawer`), `ActivityBarView.swift` (launcher click), `BuiltInPanels.swift` (SQL `prefersDrawer`).
**Group D** — Modify `TabContainerController.swift` (outer split + drawer mount + reveal→drawer), `PanelProfile.swift` (default profiles), `BuiltInPanels.swift`.
**Group E** — Modify `PanelRegistry.swift` (drop controller cache), `TabContainerController.swift` (per-container cache + rebindAIChat), `AppDelegate.swift` (rebind call sites).

---

## Group A — PanelProfile drawer + Equatable + dedupe

### Task A1: `DockEdge` + drawer fields + `Equatable` + tolerant Codable

**Files:** Modify `Sources/Simpleton/Panels/PanelProfile.swift`; Create `Tests/CoreChecks/PanelProfileChecks.swift`; Modify `Tests/CoreChecks/main.swift`.

**Interfaces produced:** `enum DockEdge: String, Codable, Equatable { case bottom, top, trailing }`; `PanelProfile.bottomActivePanelID: String?`, `.drawerEdge: DockEdge = .bottom`, `.drawerSize: CGFloat = 260`; `PanelProfile: Equatable`; `mutating func setDrawer(id: String?)`, `mutating func closeDrawer()`.

- [ ] **Step 1: Add the enum + fields + Equatable + tolerant init**

Replace the `struct PanelProfile` declaration:
```swift
enum DockEdge: String, Codable, Equatable {
    case bottom, top, trailing
}

struct PanelProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var leftPanelIDs: [String]
    var rightPanelIDs: [String]
    var leftActivePanelID: String?
    var rightActivePanelID: String?
    var leftWidth: CGFloat = 240
    var rightWidth: CGFloat = 320
    /// The GUI client panel docked in the edge drawer (nil = drawer closed).
    var bottomActivePanelID: String?
    /// Which edge the drawer sits on.
    var drawerEdge: DockEdge = .bottom
    /// Drawer height (bottom/top) or width (trailing), in points.
    var drawerSize: CGFloat = 260

    init(
        id: UUID = UUID(), name: String, leftPanelIDs: [String], rightPanelIDs: [String],
        leftActivePanelID: String?, rightActivePanelID: String?, leftWidth: CGFloat = 240,
        rightWidth: CGFloat = 320, bottomActivePanelID: String? = nil,
        drawerEdge: DockEdge = .bottom, drawerSize: CGFloat = 260
    ) {
        self.id = id
        self.name = name
        self.leftPanelIDs = leftPanelIDs
        self.rightPanelIDs = rightPanelIDs
        self.leftActivePanelID = leftActivePanelID
        self.rightActivePanelID = rightActivePanelID
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.bottomActivePanelID = bottomActivePanelID
        self.drawerEdge = drawerEdge
        self.drawerSize = drawerSize
    }

    /// Tolerant decode so profiles.json written before the drawer fields still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        leftPanelIDs = try c.decodeIfPresent([String].self, forKey: .leftPanelIDs) ?? []
        rightPanelIDs = try c.decodeIfPresent([String].self, forKey: .rightPanelIDs) ?? []
        leftActivePanelID = try c.decodeIfPresent(String.self, forKey: .leftActivePanelID)
        rightActivePanelID = try c.decodeIfPresent(String.self, forKey: .rightActivePanelID)
        leftWidth = try c.decodeIfPresent(CGFloat.self, forKey: .leftWidth) ?? 240
        rightWidth = try c.decodeIfPresent(CGFloat.self, forKey: .rightWidth) ?? 320
        bottomActivePanelID = try c.decodeIfPresent(String.self, forKey: .bottomActivePanelID)
        drawerEdge = try c.decodeIfPresent(DockEdge.self, forKey: .drawerEdge) ?? .bottom
        drawerSize = try c.decodeIfPresent(CGFloat.self, forKey: .drawerSize) ?? 260
    }
}
```

- [ ] **Step 2: Add the drawer mutation helpers**

In the mutation-helpers extension (with `togglePanel`/`activatePanel`):
```swift
    /// Set (or clear, with nil) the drawer's active GUI panel.
    mutating func setDrawer(id: String?) {
        bottomActivePanelID = id
    }

    /// Close the drawer.
    mutating func closeDrawer() {
        bottomActivePanelID = nil
    }
```

- [ ] **Step 3: Write the checks**

Create `Tests/CoreChecks/PanelProfileChecks.swift`:
```swift
// Tests/CoreChecks/PanelProfileChecks.swift
import Foundation

func runPanelProfileChecks(_ t: TestRunner) {
    t.suite("PanelProfile drawer fields round-trip + Equatable") {
        var p = PanelProfile(
            name: "P", leftPanelIDs: ["a"], rightPanelIDs: [], leftActivePanelID: "a",
            rightActivePanelID: nil)
        t.expect(p.bottomActivePanelID == nil, "drawer closed by default")
        t.expectEqual(p.drawerEdge, DockEdge.bottom, "default edge bottom")
        p.setDrawer(id: "sql")
        t.expectEqual(p.bottomActivePanelID, "sql", "setDrawer sets id")
        p.closeDrawer()
        t.expect(p.bottomActivePanelID == nil, "closeDrawer clears")
        // Equatable
        let a = PanelProfile(name: "X", leftPanelIDs: [], rightPanelIDs: [], leftActivePanelID: nil, rightActivePanelID: nil)
        var b = a
        t.expect(a == b, "identical profiles equal")
        b.drawerSize = 300
        t.expect(a != b, "drawerSize change makes them unequal")
    }

    t.suite("PanelProfile tolerant decode — legacy profile without drawer fields") {
        let legacy = #"{"id":"33333333-3333-3333-3333-333333333333","name":"old","leftPanelIDs":["connections"],"rightPanelIDs":[],"leftActivePanelID":"connections","rightActivePanelID":null}"#
        do {
            let p = try JSONDecoder().decode(PanelProfile.self, from: Data(legacy.utf8))
            t.expectEqual(p.name, "old", "name decoded")
            t.expect(p.bottomActivePanelID == nil, "bottomActivePanelID defaults nil")
            t.expectEqual(p.drawerEdge, DockEdge.bottom, "drawerEdge defaults bottom")
            t.expectEqual(p.drawerSize, 260, "drawerSize defaults 260")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
```
Note: `PanelProfile`/`DockEdge` live in the `Simpleton` executable target, but `CoreChecks` depends only on `SimpletonCore`. **If `PanelProfile` is not visible to CoreChecks, keep these two suites but move them into an existing app-buildable check target is not possible** — instead verify at build time only and drop this file. To decide: run `grep -n "import Simpleton" Tests/CoreChecks/*.swift`; CoreChecks cannot import the executable target, so **PanelProfile checks must be build-verified, not CoreChecks-verified.** Therefore: **do not create this file**; instead confirm via `swift build` that the new fields/helpers compile, and rely on the app build. (Kept the test text above only as documentation of intended behavior.)

- [ ] **Step 4: Verify**

Run `swift build 2>&1 | tail -1` → `Build complete!` (Equatable synthesizes; tolerant init compiles). `swift run CoreChecks` → unchanged count, still all pass. Do **not** register a PanelProfile suite in main.swift (target-visibility per Step 3).

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/PanelProfile.swift
git commit -m "feat(panels): add drawer slot + DockEdge + Equatable to PanelProfile"
```

### Task A2: `.removeDuplicates()` on the profile sink

**Files:** Modify `Sources/Simpleton/TabContainerController.swift`.

- [ ] **Step 1: Add removeDuplicates**

In `subscribeToRegistry()`, change the sink:
```swift
        registry.$activeProfile
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.updatePanels(for: profile)
            }
            .store(in: &cancellables)
```
(Requires `PanelProfile: Equatable` from A1.)

- [ ] **Step 2: Verify + commit**

`swift build` → complete; `swift run CoreChecks` → pass; `bash scripts/e2e/workspace-e2e.sh` → `SIMP-WSE2E RESULT PASS` (profile switching still works).
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/TabContainerController.swift
git commit -m "perf(panels): dedupe activeProfile emissions so no-op assignments don't rebuild"
```

---

## Group B — Text-client CLI panes

### Task B1: `SQLClientCommand` builder + checks

**Files:** Create `Sources/SimpletonSQL/SQLClientCommand.swift`, `Tests/CoreChecks/SQLClientCommandChecks.swift`; Modify `Tests/CoreChecks/main.swift`.

**Interfaces produced:** `SQLClientCommand` with `static func candidates(for kind: ConnectionKind) -> [String]` and `static func build(for connection: Connection, password: String?) -> (args: [String], environment: [String])?` (nil for unsupported kinds).

- [ ] **Step 1: Write the builder**

Create `Sources/SimpletonSQL/SQLClientCommand.swift`:
```swift
// Sources/SimpletonSQL/SQLClientCommand.swift
import Foundation
import SimpletonCore

/// Pure builder for launching a terminal CLI client for a `Connection`. The password is placed in
/// the process ENVIRONMENT (PGPASSWORD/MYSQL_PWD), never on argv, so it can't leak via `ps` or shell
/// history. Executable *resolution* (which candidate is on disk) happens in the app; this is pure.
public enum SQLClientCommand {
    /// Preferred → fallback executables per kind (nicer TUI first, standard client second).
    public static func candidates(for kind: ConnectionKind) -> [String] {
        switch kind {
        case .postgres: return ["pgcli", "psql"]
        case .mysql: return ["mycli", "mysql"]
        case .sqlite: return ["litecli", "sqlite3"]
        default: return []
        }
    }

    /// Build (args, environment) for the resolved executable of `connection.kind`. The same args
    /// work for both the TUI and the standard client of each family. Returns nil for non-SQL kinds.
    public static func build(for connection: Connection, password: String?) -> (args: [String], environment: [String])? {
        switch connection.kind {
        case .postgres:
            var args = ["-h", connection.host ?? "localhost", "-p", String(connection.port ?? 5432)]
            if let u = connection.username { args += ["-U", u] }
            if let db = connection.params["database"], !db.isEmpty { args += ["-d", db] }
            let env = password.map { ["PGPASSWORD=\($0)"] } ?? []
            return (args, env)
        case .mysql:
            var args = ["-h", connection.host ?? "127.0.0.1", "-P", String(connection.port ?? 3306)]
            if let u = connection.username { args += ["-u", u] }
            if let db = connection.params["database"], !db.isEmpty { args += [db] }
            let env = password.map { ["MYSQL_PWD=\($0)"] } ?? []
            return (args, env)
        case .sqlite:
            return ([connection.params["path"] ?? ""], [])
        default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Write the checks**

Create `Tests/CoreChecks/SQLClientCommandChecks.swift`:
```swift
// Tests/CoreChecks/SQLClientCommandChecks.swift
import Foundation
import SimpletonCore
import SimpletonSQL

func runSQLClientCommandChecks(_ t: TestRunner) {
    t.suite("SQLClientCommand.candidates") {
        t.expectEqual(SQLClientCommand.candidates(for: .postgres), ["pgcli", "psql"], "postgres TUI→std")
        t.expectEqual(SQLClientCommand.candidates(for: .mysql), ["mycli", "mysql"], "mysql TUI→std")
        t.expectEqual(SQLClientCommand.candidates(for: .sqlite), ["litecli", "sqlite3"], "sqlite TUI→std")
        t.expect(SQLClientCommand.candidates(for: .s3).isEmpty, "s3 has no CLI client")
    }

    t.suite("SQLClientCommand.build — password goes to env, never args") {
        let pg = Connection(
            name: "p", kind: .postgres, host: "db", port: 5432, username: "app",
            params: ["database": "appdb"])
        let built = SQLClientCommand.build(for: pg, password: "s3cret")
        t.expect(built != nil, "postgres builds")
        t.expectEqual(built?.args, ["-h", "db", "-p", "5432", "-U", "app", "-d", "appdb"], "pg args")
        t.expectEqual(built?.environment, ["PGPASSWORD=s3cret"], "pg password in env")
        t.expect(!(built?.args.contains("s3cret") ?? true), "password NOT in args")

        let my = Connection(name: "m", kind: .mysql, host: "h", port: 3306, username: "u", params: ["database": "d"])
        let mb = SQLClientCommand.build(for: my, password: "pw")
        t.expectEqual(mb?.environment, ["MYSQL_PWD=pw"], "mysql password in env")
        t.expect(!(mb?.args.contains("pw") ?? true), "mysql password NOT in args")

        let lite = Connection(name: "l", kind: .sqlite, params: ["path": "/tmp/x.db"])
        let lb = SQLClientCommand.build(for: lite, password: nil)
        t.expectEqual(lb?.args, ["/tmp/x.db"], "sqlite args = path")
        t.expect(lb?.environment.isEmpty ?? false, "sqlite no env")

        t.expect(SQLClientCommand.build(for: Connection(name: "s", kind: .s3), password: nil) == nil, "s3 → nil")
    }
}
```
Register in `Tests/CoreChecks/main.swift` (async group not needed — sync). Add after `runSQLDriverChecks` registration is async; add a sync line in the Models group:
```swift
runSQLClientCommandChecks(runner)
```

- [ ] **Step 3: Verify + commit**

`swift build` → complete; `swift run CoreChecks` → all pass (new suites present).
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonSQL/SQLClientCommand.swift Tests/CoreChecks/SQLClientCommandChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(sql): add pure CLI-client command builder (env-based credentials)"
```

### Task B2: `ConnectionType.client` + `PaneController.startClient`

**Files:** Modify `Sources/SimpletonCore/Models/PaneState.swift`, `Sources/Simpleton/PaneController.swift`.

**Interfaces produced:** `ConnectionType.client(connectionID: UUID)`; `PaneController.startClient(connection: Connection, secret: ConnectionSecret?)`.

- [ ] **Step 1: Add the enum case**

In `PaneState.swift`:
```swift
public enum ConnectionType: Equatable {
    case local(shell: String, workingDirectory: String)
    case ssh(bookmarkID: UUID)
    case client(connectionID: UUID)
}
```

- [ ] **Step 2: Add executable resolver + startClient**

In `PaneController.swift`, add (after `startSSH`). The resolver mirrors `findDocker`'s fixed-path search but per candidate and also honors PATH dirs:
```swift
    /// Resolve the first client executable that exists on disk for `kind` (TUI preferred).
    private func resolveClientExecutable(for kind: ConnectionKind) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/homebrew/opt/mysql-client@8.4/bin"]
        for name in SQLClientCommand.candidates(for: kind) {
            for dir in dirs {
                let path = dir + "/" + name
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Start a text (CLI) client for a data connection. Password is passed via environment.
    func startClient(connection: Connection, secret: ConnectionSecret?) {
        guard let executable = resolveClientExecutable(for: connection.kind),
            let built = SQLClientCommand.build(for: connection, password: secret?.password)
        else {
            let names = SQLClientCommand.candidates(for: connection.kind).joined(separator: " or ")
            bannerManager?.showError(message: "Install \(names) to open a text client for \(connection.name)")
            return
        }
        terminalView.terminate()
        connectionType = .client(connectionID: connection.id)
        state = .running
        onTitleChange?(statusTitle(connection.name))
        terminalView.startProcess(
            executable: executable,
            args: built.args,
            environment: built.environment.isEmpty ? nil : built.environment,
            execName: nil,
            currentDirectory: nil)
    }
```
Add `import SimpletonSQL` at the top of `PaneController.swift` if not present (it now references `SQLClientCommand`). Verify `PaneController.swift` has `bannerManager`, `onTitleChange`, `statusTitle(_:)`, and mutable `connectionType`/`state` (it does — used by `startSSH`).

- [ ] **Step 3: Verify + commit**

`swift build` → complete (the `ConnectionType` switch is exhaustive everywhere — if the compiler flags a non-exhaustive switch over `ConnectionType` elsewhere, add a `case .client: …` arm mirroring `.ssh` or a sensible default; search `case .ssh` to find them). `swift run CoreChecks` → pass; e2e PASS.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Models/PaneState.swift Sources/Simpleton/PaneController.swift
git commit -m "feat(panes): add .client connection type and startClient (CLI over env creds)"
```

### Task B3: `openClientPane` + drag-a-connection drop

**Files:** Modify `Sources/Simpleton/TabContainerController.swift`, `Sources/Simpleton/TerminalDropTarget.swift`, `Sources/Simpleton/Panels/Connections/DataConnectionRow.swift`, `Sources/Simpleton/Panels/Connections/ConnectionColor.swift` (notification).

**Interfaces produced:** `.simpletonOpenConnectionText` (object = connection `id: UUID`); `TabContainerController.openClientPane(connection:secret:direction:)`; the drag UTType string `"com.simpleton.connection-id"`.

- [ ] **Step 1: Add the notification**

In `ConnectionColor.swift`, alongside `.simpletonOpenConnectionGUI`:
```swift
    /// Posted (object = connection `id: UUID`) to open that connection as a text (CLI) client pane.
    static let simpletonOpenConnectionText = Notification.Name("simpletonOpenConnectionText")
```

- [ ] **Step 2: `openClientPane` (factory-swap, mirrors openSSHConnection)**

In `TabContainerController.swift`, add:
```swift
    func openClientPane(connection: Connection, secret: ConnectionSecret?, direction: SplitDirection) {
        let previousFactory = splitController.paneFactory
        splitController.paneFactory = { [weak self] paneID in
            guard let self = self else {
                return PaneController(
                    id: paneID, frame: .zero,
                    connectionType: .local(shell: "/bin/zsh", workingDirectory: NSHomeDirectory()))
            }
            let cwd = self.splitController.panes[self.splitController.focusedPaneID]?.currentDirectory
            let pane = self.createPane(id: paneID, inheritedWorkingDirectory: cwd)
            pane.startClient(connection: connection, secret: secret)
            return pane
        }
        splitController.splitFocusedPane(direction: direction)
        splitController.paneFactory = previousFactory
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }
```

- [ ] **Step 3: Observe the text-open notification**

Add an observer next to `openConnectionObserver` (property `openConnectionTextObserver: NSObjectProtocol?`, added to the teardown list). In the observer-setup block:
```swift
        openConnectionTextObserver = NotificationCenter.default.addObserver(
            forName: .simpletonOpenConnectionText, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self, self.view.window?.isKeyWindow == true,
                let id = note.object as? UUID
            else { return }
            let dir = self.appSupportURL  // support dir for ConnectionStore
            Task { [weak self] in
                let store = ConnectionStore(directory: dir)
                guard let connection = await store.connection(for: id) else { return }
                let secret = CredentialStore.secret(for: id)
                await MainActor.run { self?.openClientPane(connection: connection, secret: secret, direction: .vertical) }
            }
        }
```
Confirm the container has an app-support URL to build `ConnectionStore` (search how `makeContext()` provides `appSupportDir` — reuse that same URL; if it's `context.appSupportDir`, capture it as `self.appSupportURL` or read from the existing config). If no such stored URL exists, add one set at init from the same source `makeContext()` uses.

- [ ] **Step 4: Accept the connection-id drop on the terminal**

In `TerminalDropTarget.swift`, register the extra type and handle it:
```swift
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.simpleton.connection-id")])
```
In `performDragOperation`, before the file-URL handling, add:
```swift
        let connType = NSPasteboard.PasteboardType("com.simpleton.connection-id")
        if let idString = sender.draggingPasteboard.string(forType: connType),
            let id = UUID(uuidString: idString) {
            NotificationCenter.default.post(name: .simpletonOpenConnectionText, object: id)
            return true
        }
```
(`.simpletonOpenConnectionText` is defined in the `Simpleton` target via ConnectionColor.swift — same target, so visible here.) Keep `draggingEntered` returning `.copy`.

- [ ] **Step 5: Make the connection row draggable**

In `DataConnectionRow.swift`, add `.onDrag` to the `Button` (emit the id on the custom type):
```swift
        .onDrag {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: "com.simpleton.connection-id", visibility: .all
            ) { completion in
                completion(Data(connection.id.uuidString.utf8), nil)
                return nil
            }
            return provider
        }
```

- [ ] **Step 6: Verify + manual**

`swift build` → complete; `swift run CoreChecks` → pass; e2e PASS. Manual: drag a SQLite Data Connection into the terminal → a new split pane opens running `sqlite3 <path>`; drag a Postgres connection → `psql`/`pgcli` opens (or a banner if none installed); confirm `ps -ax | grep psql` shows **no password in argv**.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/TabContainerController.swift Sources/Simpleton/TerminalDropTarget.swift Sources/Simpleton/Panels/Connections/DataConnectionRow.swift Sources/Simpleton/Panels/Connections/ConnectionColor.swift
git commit -m "feat(panes): drag a data connection into the terminal to open a CLI client pane"
```

---

## Group C — Hideable launcher rail

### Task C1: `showToolLauncher` preference + rail hide

**Files:** Modify `Sources/SimpletonCore/Models/AppConfig.swift`, `Sources/Simpleton/Views/PreferencesWindow.swift`, `Sources/Simpleton/TabContainerController.swift`.

**Interfaces produced:** `AppearanceConfig.showToolLauncher: Bool` (default `true`).

- [ ] **Step 1: Add the config field**

In `AppearanceConfig`: add `public var showToolLauncher: Bool`, add it to the memberwise init (default `true`) + assignment, add `showToolLauncher` to `CodingKeys`, and in the tolerant `init(from:)`:
```swift
        showToolLauncher = try c.decodeIfPresent(Bool.self, forKey: .showToolLauncher) ?? d.showToolLauncher
```

- [ ] **Step 2: Preferences toggle**

In `PreferencesWindow.swift`'s "Window" section (next to `thinStrokes`):
```swift
    Toggle("Show tool launcher rail", isOn: $config.appearance.showToolLauncher)
        .onChange(of: config.appearance.showToolLauncher) { onChanged(config) }
```

- [ ] **Step 3: Hide the right rail when disabled**

In `TabContainerController.updateRightBarVisibility(for:)`, combine the empty check with the config flag:
```swift
    private func updateRightBarVisibility(for profile: PanelProfile) {
        let show = appConfig().appearance.showToolLauncher && !profile.rightPanelIDs.isEmpty
        rightBarWidthConstraint?.constant = show ? 40 : 0
        rightBarHost?.isHidden = !show
    }
```
Confirm the container has `appConfig()` (it builds `makeContext()` with `appConfig`); if the accessor differs, use the same source `makeContext()` uses. Also call `updateRightBarVisibility(for: registry.activeProfile)` from wherever config changes are applied to panes (search `applyConfigToAllPanes` / the config-changed path) so toggling the preference live-updates.

- [ ] **Step 4: Verify + commit**

`swift build` → complete; `swift run CoreChecks` → pass; e2e PASS. Manual: toggle "Show tool launcher rail" off → right rail collapses; on → returns.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Models/AppConfig.swift Sources/Simpleton/Views/PreferencesWindow.swift Sources/Simpleton/TabContainerController.swift
git commit -m "feat(panels): add hideable tool launcher rail preference"
```

### Task C2: `prefersDrawer` panel flag

**Files:** Modify `Sources/Simpleton/Panels/PanelDefinition.swift`, `Sources/Simpleton/Panels/ActivityBarView.swift`, `Sources/Simpleton/Panels/BuiltInPanels.swift`.

**Interfaces produced:** `PanelDefinition.prefersDrawer: Bool` (default `false`).

- [ ] **Step 1: Add the flag**

In `PanelDefinition`, add `let prefersDrawer: Bool` with a default. Since it's a struct with a memberwise-style init used positionally in `BuiltInPanels`, give it a default by adding it as the LAST stored property AND updating the initializer to `prefersDrawer: Bool = false`. If `PanelDefinition` uses the synthesized memberwise init (no explicit init), add an explicit init preserving current call sites with `prefersDrawer` defaulted last. (Search `PanelDefinition(` to confirm call sites pass args by label; all existing ones omit `prefersDrawer`, so a defaulted trailing param is source-compatible.)

- [ ] **Step 2: Launcher click routes prefersDrawer panels to the drawer**

In `ActivityBarView.togglePanel(id:)`, branch on the definition:
```swift
    private func togglePanel(id: String) {
        var profile = registry.activeProfile
        if side == .right,
            let def = registry.definitions.first(where: { $0.id == id }), def.prefersDrawer {
            profile.setDrawer(id: profile.bottomActivePanelID == id ? nil : id)
        } else {
            profile.togglePanel(id: id, on: side)
        }
        registry.activeProfile = profile
    }
```

- [ ] **Step 3: SQL prefers the drawer**

In `BuiltInPanels.swift`, set `prefersDrawer: true` on the `sql` `PanelDefinition` (pass the new trailing arg).

- [ ] **Step 4: Verify + commit**

`swift build` → complete (drawer mount lands in Group D; here the click just sets `bottomActivePanelID`, harmless until D renders it). `swift run CoreChecks` → pass; e2e PASS.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/PanelDefinition.swift Sources/Simpleton/Panels/ActivityBarView.swift Sources/Simpleton/Panels/BuiltInPanels.swift
git commit -m "feat(panels): add prefersDrawer flag routing launcher clicks to the drawer"
```

---

## Group D — Drawer restructure + SQL fold-in

### Task D1: Outer split with a bottom drawer slot

**Files:** Modify `Sources/Simpleton/TabContainerController.swift`.

**Interfaces produced:** `TabContainerController.activateDrawer(id: String?)`; a stored `outerSplit: NSSplitView?`, `drawerHost` VC + `drawerPanelID`.

- [ ] **Step 1: Wrap contentSplit in an outer vertical-stacking split**

Add stored properties near `contentSplit`:
```swift
    private var outerSplit: NSSplitView?
    private var drawerPanelVC: NSViewController?
    private var drawerPanelID: String?
```
In `loadView`, after creating `contentSplit` (`split`), wrap it:
```swift
        let outer = NSSplitView(frame: frame)
        outer.isVertical = false  // horizontal divider → top/bottom stack
        outer.dividerStyle = .thin
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.addArrangedSubview(split)   // contentSplit is the main (top) slot
        outerSplit = outer
```
Then have `mountActivityBars` pin **`outerSplit`** (not `contentSplit`) between the rails: in `mountActivityBars`, replace the four `split.*Anchor` constraints that pin `split` to the container with the same anchors on `outerSplit`, and add `outerSplit` as the container subview instead of `split`. (contentSplit `split` is now a child of `outerSplit`, no longer pinned to the container directly.) Keep `updateRightBarVisibility(for:)` call.

- [ ] **Step 2: Mount/unmount the drawer in updatePanels**

Add a drawer step at the end of `updatePanels(for:)`, before the divider-position `DispatchQueue.main.async`:
```swift
        // ── Drawer (edge-docked GUI client) ─────────────────────
        if let vc = drawerPanelVC {
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            drawerPanelVC = nil
            drawerPanelID = nil
        }
        if let id = profile.bottomActivePanelID,
            let outer = outerSplit,
            let vc = panelRegistry?.makeController(for: id, context: makeContext())
        {
            addChild(vc)
            vc.view.frame = NSRect(x: 0, y: 0, width: outer.bounds.width, height: profile.drawerSize)
            if profile.drawerEdge == .top {
                outer.insertArrangedSubview(vc.view, at: 0)
            } else {
                outer.addArrangedSubview(vc.view)  // .bottom (and .trailing treated as bottom for v1)
            }
            drawerPanelVC = vc
            drawerPanelID = id
        }
```
And in the divider-position async block, set the outer divider from `drawerSize`:
```swift
            if let outer = self.outerSplit, self.drawerPanelVC != nil {
                let idx = 0
                let pos = profile.drawerEdge == .top
                    ? profile.drawerSize
                    : outer.bounds.height - profile.drawerSize
                outer.setPosition(pos, ofDividerAt: idx)
            }
```

- [ ] **Step 3: activateDrawer helper**

```swift
    func activateDrawer(id: String?) {
        guard let registry = panelRegistry else { return }
        var profile = registry.activeProfile
        profile.setDrawer(id: id)
        registry.activeProfile = profile
    }
```

- [ ] **Step 4: Verify + manual**

`swift build` → complete; `swift run CoreChecks` → pass; **e2e PASS** (the outer-split wrap must not break session restore geometry). Manual: with a right-rail SQL launcher (prefersDrawer), click it → SQL panel appears in a bottom drawer; drag the divider to resize; click again → closes.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/TabContainerController.swift
git commit -m "feat(panels): add bottom edge-dockable drawer slot hosting a GUI panel"
```

### Task D2: SQL folds into the drawer + reveal targets it

**Files:** Modify `Sources/Simpleton/TabContainerController.swift` (reveal observer), `Sources/Simpleton/Panels/PanelProfile.swift` (default profiles), persist drawerSize on divider drag.

- [ ] **Step 1: Reveal targets the drawer**

In the `openConnectionObserver` (from sub-project 1), replace the right-side activation with drawer activation:
```swift
            // Reveal the SQL panel in the drawer so it can consume the pending connection.
            guard registry.activeProfile.bottomActivePanelID != PanelProfile.PanelID.sql else { return }
            var profile = registry.activeProfile
            profile.setDrawer(id: PanelProfile.PanelID.sql)
            registry.activeProfile = profile
```

- [ ] **Step 2: Default placement**

In `PanelProfile.defaultProfiles`, change the Developer profile's `rightPanelIDs: ["sql"]` to `rightPanelIDs: ["sql"]` **kept as a launcher entry** but `rightActivePanelID: nil` (already nil). The SQL panel is now launched into the drawer via the rail click / reveal, not shown on the right by default — no change needed beyond confirming `rightActivePanelID` stays nil. (SQL remains in `rightPanelIDs` so its launcher icon shows in the rail.)

- [ ] **Step 3: Persist drawerSize on divider drag**

Add an `NSSplitViewDelegate` hook for `outerSplit` (or observe `splitViewDidResizeSubviews`) that reads the drawer height and writes it back to the active profile (debounced via a short `DispatchQueue.main.asyncAfter` coalesce), then `registry.activeProfile = profile`. Minimal version: on `splitViewDidResizeSubviews`, compute the drawer's current height, set `profile.drawerSize`, assign back only if changed by >1pt (avoids feedback via `.removeDuplicates()`).

- [ ] **Step 4: Verify + manual + commit**

`swift build` → complete; `swift run CoreChecks` → pass; e2e PASS. Manual: click a Data Connection → SQL opens in the drawer focused on it + connects; resize the drawer, close/reopen → size remembered.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/TabContainerController.swift Sources/Simpleton/Panels/PanelProfile.swift
git commit -m "feat(panels): dock the SQL GUI client in the drawer; reveal targets it"
```

---

## Group E — Per-container controller cache (HIGHEST RISK, LAST)

> If any step here breaks an existing panel (mount, switch, AI rebind) or the e2e, **STOP, revert the group, and report** — do not force it.

### Task E1: Move the controller cache off the singleton registry

**Files:** Modify `Sources/Simpleton/Panels/PanelRegistry.swift`, `Sources/Simpleton/TabContainerController.swift`, `Sources/Simpleton/AppDelegate.swift`.

- [ ] **Step 1: Add a per-container cache + builder in TabContainerController**

```swift
    private var panelControllers: [String: NSViewController] = [:]

    /// Build (or reuse this container's cached) controller for a panel id.
    private func makePanelController(for id: String) -> NSViewController? {
        if let cached = panelControllers[id] { return cached }
        guard let def = panelRegistry?.definitions.first(where: { $0.id == id }) else { return nil }
        let vc = def.make(makeContext())
        panelControllers[id] = vc
        return vc
    }
```
Replace the three `panelRegistry?.makeController(for: id, context: makeContext())` call sites in `updatePanels` (left, right, drawer) with `makePanelController(for: id)`.

- [ ] **Step 2: Per-container AI rebind**

Move `rebindAIChat` logic into the container: where the container currently calls `panelRegistry?.rebindAIChat(to: tabConversation)`, replace with a local rebind of this container's cached AI controller:
```swift
    private func rebindAIChatLocal(to conversation: TabConversation?) {
        guard let controller = panelControllers[PanelProfile.PanelID.aiChat] as? AIChatPanelController else { return }
        controller.conversation = conversation
    }
```
and call `rebindAIChatLocal(to:)` from the same spot(s). Remove the `PanelRegistry.rebindAIChat` calls (and the method from `PanelRegistry`, plus its `controllers` cache, `makeController`, `evictController`). Search all references to `registry.makeController`/`.rebindAIChat`/`.evictController` and update/remove.

- [ ] **Step 3: Verify exhaustively**

`swift build` → complete (no reference to the removed registry methods remains). `swift run CoreChecks` → pass. **e2e PASS.** Manual regression: every left panel (connections, history, file-browser, notes, snippets, environment, processes, ssh-tunnels, git, docker, data-connections) mounts and switches; AI chat opens (header button) and rebinds when switching tabs; the SQL drawer works; open a **second window** and confirm each shows its own panels independently (the original bug — a panel no longer jumps between windows).

- [ ] **Step 4: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/PanelRegistry.swift Sources/Simpleton/TabContainerController.swift Sources/Simpleton/AppDelegate.swift
git commit -m "refactor(panels): cache panel controllers per container to fix multi-window targeting"
```

---

## Task F: Final verification

- [ ] **Step 1:** `swift build 2>&1 | tail -1` → `Build complete!`
- [ ] **Step 2:** `swift run CoreChecks 2>&1 | tail -1` → all pass.
- [ ] **Step 3:** `swift format lint --recursive --parallel --strict Sources Tests` → exit 0.
- [ ] **Step 4:** `bash scripts/e2e/workspace-e2e.sh` → `SIMP-WSE2E RESULT PASS`.

---

## Self-Review

**Spec coverage:** §2a.1 profile drawer+Equatable → A1; §2a.2 registry fix → E1 (per-container) + A2 (dedupe); §2a.3 contentSplit restructure → D1; §2a.4 launcher hideable → C1/C2; §2a.5 SQL fold-in → D2; §2a.6 tests → A1(build)/CoreChecks; §2b.1 startClient → B1/B2; §2b.2 openClientPane → B3; §2b.3 drag→drop → B3; §2b.4 tests → B1. Non-goals (.trailing full, S3 client) flagged.

**Placeholder scan:** the A1-Step-3 test-file note explicitly resolves to "build-verify, don't create the CoreChecks file" (target visibility) — not a placeholder but a real decision, stated. B1/B2 tests are concrete. The D2-Step-3 debounce is described with the exact coalescing rule.

**Type consistency:** `PanelProfile.setDrawer(id:)`/`bottomActivePanelID`/`drawerEdge`/`drawerSize`/`DockEdge` consistent A1→D. `SQLClientCommand.candidates(for:)`/`build(for:password:)` consistent B1→B2. `ConnectionType.client(connectionID:)` B2, matched in `startClient`. `.simpletonOpenConnectionText` B3. `makePanelController(for:)` replaces `registry.makeController` at all three call sites in E1. `activateDrawer`/`setDrawer` names stable.

**Risk isolation:** E is last and self-contained; its STOP-and-flag instruction is explicit.
