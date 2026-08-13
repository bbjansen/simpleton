# SFTP file-browser client panel

Status: implemented. Date: 2026-08-14.

## Goal

Add an SFTP remote file-browser as a GUI client panel, mirroring the existing SQL
client (`SimpletonSQL` + SQL panel). A user picks a saved `.sftp` connection, connects,
browses remote directories, and downloads / uploads / makes / renames / deletes files.

## Architecture

Same two-layer split as SQL:

- **`SimpletonSFTP`** (new SPM library target) — the data layer, isolating the heavy
  SwiftNIO-SSH / Citadel stack from `SimpletonCore` and the app.
  - `SFTPBackend` — the backend-agnostic protocol seam (mirror of `SQLDriver`): `connect`,
    `list(path:)`, `realPath(_:)`, `download(path:)`, `upload(path:data:)`,
    `makeDirectory(path:)`, `rename(from:to:)`, `remove(path:)`, `removeDirectory(path:)`,
    `close`. All async; every failure maps to `SFTPError`.
  - Pure `Sendable` model: `FileEntry { name, path, isDirectory, size, modified?, permissions? }`,
    `FileAttributes`, and `SFTPError` (`.auth`, `.hostKey`, `.notFound`, `.connectionFailed`,
    `.unsupported`).
  - `KnownHostsValidator` — a real TOFU host-key validator (see below), plus a small
    `KnownHostsFile` line parser (host/key-type/base64) that is unit-tested.
  - `CitadelSFTPBackend` — concrete `SFTPBackend` over Citadel (`SSHClient.connect` +
    `openSFTP()`), `@unchecked Sendable` (the `SSHClient`/`SFTPClient` are assigned once in
    `connect()`).
  - `SFTPBackendFactory.make(_:secret:)` — switches on `connection.kind`; `.sftp` →
    `CitadelSFTPBackend`, everything else throws `.unsupported`.
- **App panel** — `Panels/SFTP/SFTPPanelModel.swift` + `SFTPPanelView.swift`, mirroring the
  SQL panel (own connection Picker filtering `.sftp`, `ClientPanelScaffold`,
  `themedGlass(DT.surface)`, pending-open consume via
  `PendingClientOpen.shared.take(for: PanelProfile.PanelID.sftp)`).

## Backend / dependency

Citadel, pinned `exact: "0.12.1"` (SwiftNIO-SSH based SFTP). Added to the `SimpletonSFTP`
target and, transitively, to `Simpleton` and `CoreChecks`. **SFTP only** — classic FTP
(CFNetwork) is deprecated and not attempted.

Auth is read from `Connection` + `ConnectionSecret`:
- Host from `connection.host`, port from `connection.port ?? 22`, user from `connection.username`.
- Password auth: `ConnectionSecret.password`.
- Public-key auth: `params["identityFile"]` (tilde-expanded exactly like `SSHManager` via
  `NSString(string:).expandingTildeInPath`), parsed with Citadel's OpenSSH key API, optional
  `ConnectionSecret.passphrase`.
- No secrets ever go into `params`.

## Host-key verification (TOFU)

Production must not `acceptAnything()`. `KnownHostsValidator` implements Trust-On-First-Use
against `~/.ssh/known_hosts`:

1. Serialize the server's offered key to its OpenSSH wire form (`type base64`).
2. Look up the host (and `[host]:port` form for non-22 ports) in `~/.ssh/known_hosts`.
3. **Known + matching** → accept.
4. **Known + different key of same type** → reject with `.hostKey` (possible MITM / changed
   key), never silently trust.
5. **Unknown host** → allow-on-first-use: accept and append the key to `~/.ssh/known_hosts`
   (creating the file `0600` if absent). Documented TOFU behaviour.

The `known_hosts` line parser (`KnownHostsFile`) is a pure function and is unit-tested in
CoreChecks.

## GUI panel scope (MVP, fully implemented)

Connection bar (Picker filtered to `.sftp`, Connect/Disconnect, "+" opens the editor) →
breadcrumb + up button → directory listing table (icon, name, size, modified). Actions, all
real Citadel calls:

- **navigate**: double-click a directory row; **up** button; path starts at the server's
  real home (`realPath(".")`).
- **Download** (NSSavePanel) — streams the remote file to the chosen local URL.
- **Upload** (NSOpenPanel) — reads the local file and writes it to the current directory.
- **New Folder** — prompt, `makeDirectory`.
- **Rename** — prompt, `rename`.
- **Delete** (confirm) — `remove` for files, `removeDirectory` for directories.

Errors surface via the scaffold's unavailable state (connect failures, incl. host-key
rejection) and an inline error line (per-op failures).

## Registration

- `PanelProfile.PanelID.sftp = "sftp"`.
- `PanelDefinition.sftp` (`prefersDrawer: true`) hosting `SFTPPanelView` via `NSHostingController`.
- `AppDelegate`: `panelRegistry.register(.sftp)` +
  `GUIClientRegistry.shared.register(kinds: [.sftp], panelID: PanelProfile.PanelID.sftp)`.
- `DataConnectionEditor`: `.sftp` added to `kinds`; fields Name, Host, Port (default 22),
  User, Password (optional), Identity file (optional, with Choose…), Passphrase (optional).

## Verification

- CoreChecks `SFTPDriverChecks`: pure-model (`FileEntry` isDirectory/size, attribute mapping),
  `KnownHostsFile` line parser, `SFTPError` mapping, factory mapping (`.sftp` →
  `CitadelSFTPBackend`, `.postgres` → `.unsupported`), and an env-gated live test
  (`SIMPLETON_SFTP_TEST_HOST` / `_USER` / `_PASSWORD`) that connects and lists `.`; otherwise
  prints "SFTP live checks skipped".
- Gates: `swift build`, `swift run CoreChecks`, `swift format lint --strict`.
</content>
</invoke>
