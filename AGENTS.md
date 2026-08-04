# AGENTS.md

Rules for working in this repository — for human contributors and AI coding agents alike.
See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the fuller setup and workflow guide.

## Golden rules

1. **Never commit to `main`.** Create a branch (`feat/…`, `fix/…`, `refactor/…`, `chore/…`,
   `docs/…`, `test/…`) and open a pull request. `main` is protected and requires green CI.
2. **Conventional Commits, always.** Commit messages *and* PR titles follow
   [Conventional Commits](https://www.conventionalcommits.org) — release-please derives the version
   and changelog from them.
3. **Green before you push.** These must pass locally before opening a PR:
   - `swift build`
   - `swift run CoreChecks`
   - `scripts/dev/format.sh --check` (run `scripts/dev/format.sh` to auto-fix)
4. **Put testable logic in `SimpletonCore`** (UI-free) and add a `Tests/CoreChecks` suite for it,
   registered in `Tests/CoreChecks/main.swift`. The `Simpleton` target is the AppKit/SwiftUI app.
5. **Prefer registries/tables over scattered `switch`es** (e.g. `ProviderPreset`). Adding a case
   should be one row, not edits across five files.
6. **Expose env overrides for testability** when it avoids touching real user data — e.g.
   `SIMPLETON_SUPPORT_DIR`, `SIMPLETON_SSH_CONFIG`.
7. **Never commit secrets.** API keys live in the macOS Keychain. Redact hostnames, keys, and
   tokens from screenshots, issues, and logs.
8. **Don't hand-edit versions or `CHANGELOG.md`.** Releases are automated by release-please; pin a
   specific version with a `Release-As: x.y.z` commit footer when needed.

## Layout

- `Sources/SimpletonCore/` — pure, testable logic (models, stores, parsers). No AppKit.
- `Sources/Simpleton/` — the AppKit + SwiftUI application.
- `Tests/CoreChecks/` — the no-Xcode test runner over `SimpletonCore`.
- `scripts/dev/`, `scripts/e2e/` — dev-signing and app-bundle / UI-smoke helpers.

## CI gates

- **Build & Test** (required) — `swift build` + `swift run CoreChecks` on macOS.
- **Format check** (required) — `swift format` must report no changes.
- **SwiftLint** (advisory) — style guidance; does not block.
- **Workflow lint** (actionlint) — validates GitHub Actions YAML.
- **PR title** — must be a valid Conventional Commit.
