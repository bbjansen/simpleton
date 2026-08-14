# SQL Workspace — Design

**Status:** design for review
**Date:** 2026-08-14
**Branch:** `feature/sql-workspace-shell` (sub-project 1)

## Problem

The SQL results grid is competitive, but everything around it is cramped into
the bottom drawer: a bare `TextEditor` query field, a `maxHeight: 160` schema
list, a plain connection picker, all stacked in a short drawer
(`SQLPanelView.swift`). Real SQL clients (TablePlus / DataGrip / Postico) use a
full workspace — schema sidebar + query editor + results — with room to work.

This effort gives Simpleton a **dedicated full SQL workspace** and upgrades the
editor, schema browser, connection UX, and visual polish to compete.

## Direction (approved)

- **Form-factor:** a dedicated full workspace (not confined to the drawer).
- **Scope:** real query editor + schema-browser upgrade + connection/result
  actions + a visual polish pass.

## Architecture

### Home: a dedicated `NSWindow` with a shared model

Tabs, panes, and the drawer are all hard-typed to the terminal-centric
`TabContainerController`; hosting a non-terminal *tab* would need broad
generalization (`TabItem`/`TabManager`/`WindowController`/`SessionCoordinator`).
The least-invasive, fully-isolated home is a **standalone `NSWindow`** owned by
`AppDelegate`, whose content is `NSHostingController(rootView:
SQLWorkspaceView(model:))`. The drawer SQL panel stays as a quick-peek launcher;
an **"Expand" button** opens the full workspace window on the same session.

**Prerequisite — lift `SQLPanelModel` to an injected object.** Today
`SQLPanelView.init(appSupportDir:)` creates the model as a `@StateObject`, so the
drawer's live `SQLDriver` / connection / schema / result is private to that view
and can't be shared. We refactor to:

- `SQLPanelModel` — unchanged logic (already `@MainActor`, `@Published`
  connection/schema/result), but now **created and owned outside the view**.
- A thin **`SQLPanelController`** (NSViewController) that owns one
  `SQLPanelModel` and hosts `SQLPanelView(model:)`. The `sql` panel factory in
  `BuiltInPanels.swift` returns this controller (cached per container as today).
- `SQLPanelView.init(model:)` and `SQLWorkspaceView.init(model:)` both take the
  **same** `SQLPanelModel` instance → the drawer and the workspace are two views
  of one live session (open the workspace, and it already shows the drawer's
  connection + schema + last result).

**Opening the workspace:**
1. The drawer panel's scaffold header gains an **Expand** button that posts
   `.simpletonExpandSQLWorkspace`.
2. `AppDelegate` observes it, resolves the key window's active
   `TabContainerController`, reads the cached `SQLPanelController` from
   `panelControllers[PanelID.sql]` (via a new accessor; mirror the existing
   `rebindAIChatLocal` pattern), and opens a titled, resizable `NSWindow`
   hosting `SQLWorkspaceView(model:)`, retained in an `AppDelegate` array
   (matching the existing standalone-window pattern). Re-opening focuses the
   existing window rather than duplicating it (keyed by the model's connection).

### Layout: editor-over-results, schema sidebar left

`SQLWorkspaceView` — the DataGrip/Postico model (explicitly not the Sequel Ace
object-tab model):

```
┌───────────────────────────────────────────────────────────┐
│ toolbar: connection ● status · database/schema ▾ · Run ▾   │
├──────────────┬────────────────────────────────────────────┤
│ schema       │ query editor (tabs)                         │
│ sidebar      │  ┌ Query 1 · Query 2 · + ┐                  │
│ (tree,       │  │ SELECT … (highlighted, line #s,          │
│  search,     │  │           autocomplete)                  │
│  collapsible)│  ├──────────── draggable ─────────────────┤ │
│              │  │ results (per-statement tabs)            │ │
│              │  │  rows · timing · export CSV/JSON        │ │
└──────────────┴──┴─────────────────────────────────────────┘
```

- **Left schema sidebar** — independently collapsible (to 0), remembered width
  (~18% default). Searchable tree (schema → tables/views → columns), right-click
  Generate SELECT / INSERT / DDL, pin.
- **Center** — a vertical split: **query editor** (top) over **results**
  (bottom), draggable + persisted (~50/50 default). Editor supports multiple
  named query tabs; results show one tab per statement with row-count +
  execution time + export.
- **Toolbar** — connection status dot, a database/schema switcher bound to the
  active editor tab, Run (all) / Run-selection.
- All split proportions + collapse states persist (per the profiles/prefs
  persistence pattern — `@AppStorage` or a small workspace-layout store).

### Query editor tech (hand-rolled, zero deps)

`SQLCodeEditor` — an `NSViewRepresentable` over `NSTextView` + `NSRulerView`,
replacing the bare `TextEditor` in both the drawer panel and the workspace:

- **Highlighting** — `textStorage.delegate`; in
  `textStorage(_:didProcessEditing:…)` on `.editedCharacters`, re-highlight only
  the edited `paragraphRange` (never change length in the delegate) via a
  ~120-line single-pass SQL tokenizer (keywords case-insensitive `Set`, single
  `'…'` strings, `--` line + `/* */` block comments, numbers, quoted/backtick
  identifiers), colored from `DT.*`. Re-runs on live theme switch.
- **Line numbers** — an `NSRulerView` subclass as `verticalRulerView`.
- **Autocomplete** — `NSTextView` subclass; debounced `complete(nil)` in
  `didChangeText()`; `textView(_:completions:forPartialWordRange:…)` returns
  case-insensitive prefix matches from `model.columnsByTable.values`, then
  `model.tables`, then a static keyword `Set`. `rangeForUserCompletion`
  overridden so `table.column` and quoted identifiers complete.
- **Run** — ⌘Return (run all) / ⌘⇧Return (run selection or current statement),
  intercepted in the `NSTextView` subclass (not SwiftUI `.keyboardShortcut`).

## Sub-projects

Each is its own branch → PR → adversarial review → smoke → merge.

1. **Workspace shell (this spec's foundation).** Lift `SQLPanelModel` to an
   injected object + `SQLPanelController`; `SQLWorkspaceView` 3-zone layout
   reusing the *existing* `SQLSchemaBrowser` / current editor / `SQLResultsView`;
   the Expand button + `AppDelegate` window plumbing; persisted split/collapse
   state. Deliverable: a working full workspace window sharing the drawer's
   session, with today's components dropped in.
2. **Real query editor.** `SQLCodeEditor` (highlighting + line numbers +
   autocomplete + run-selection) + multiple named query tabs + format/prettify.
   Replaces the bare `TextEditor` everywhere.
3. **Schema browser upgrade.** Searchable collapsible tree with column details
   (type / PK / FK / nullable), Generate SELECT/INSERT/DDL, views/indexes, a
   database/schema switcher (adds `SQLDriver` introspection where needed).
4. **Connection UX + result actions + polish.** Connection status + database
   selector; per-statement result tabs; row-count/timing prominence; export to
   CSV/JSON file; saved/favorite queries; a spacing/typography/proportions pass.

## Components & interfaces (sub-project 1)

| File | Responsibility |
|---|---|
| `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift` (edit) | No logic change; now created/owned externally. |
| `Sources/Simpleton/Panels/SQL/SQLPanelController.swift` (new) | `NSViewController` owning one `SQLPanelModel`, hosting `SQLPanelView(model:)`; exposes `model`. |
| `Sources/Simpleton/Panels/SQL/SQLPanelView.swift` (edit) | `init(model:)`; add the Expand button. |
| `Sources/Simpleton/Panels/SQL/SQLWorkspaceView.swift` (new) | The 3-zone workspace (`init(model:)`), reusing existing sub-views. |
| `Sources/Simpleton/Panels/SQL/SQLWorkspaceLayout.swift` (new) | Pure, persisted split/collapse state (`@AppStorage`-backed), testable defaults. |
| `Sources/Simpleton/Panels/BuiltInPanels.swift` (edit) | `sql` factory returns `SQLPanelController`. |
| `Sources/Simpleton/TabContainerController.swift` (edit) | Accessor for the cached SQL controller (mirror `rebindAIChatLocal`). |
| `Sources/Simpleton/AppDelegate.swift` (edit) | Observe `.simpletonExpandSQLWorkspace`; open/focus the workspace `NSWindow`; retain it. |
| `Sources/Simpleton/Panels/Connections/ConnectionColor.swift` (edit) | Add the `.simpletonExpandSQLWorkspace` notification name. |

## Testing

- Pure layout-state (`SQLWorkspaceLayout`) CoreCheckable (defaults, clamping,
  persistence keys) — headless.
- A headless grid/e2e already covers the model + grid; extend the SQL e2e to
  assert the workspace view mounts and shares the model (mirror
  `sql-grid-e2e.sh`).
- Smoke: build the app, open a connection, click Expand, screenshot the
  workspace (schema sidebar + editor + results) rendering with data.

## Global constraints

- Swift 6 / SPM, no Xcode. `swift build` / `swift run CoreChecks` /
  `swift format lint --strict`.
- **Zero new dependencies** (editor is hand-rolled).
- Reuse the existing `SQLResultsView` / `SQLSchemaBrowser` / grid — do not
  reimplement the results grid.
- Theme via `DT` / `ThemeSettings`; the workspace re-themes live.
- The drawer SQL panel keeps working (same shared model); the workspace is
  additive.
- Commit messages conventional; no co-author; no AI mention.
