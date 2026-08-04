# Contributing to Simpleton

Thanks for your interest in improving Simpleton! This is an early-stage (alpha) project, so
contributions, bug reports, and ideas are all welcome.

> **In a hurry?** [**AGENTS.md**](AGENTS.md) has the crisp rules (branching, Conventional Commits,
> the checks to run, where code goes). This document is the fuller how-to.

## Getting set up

Requirements:

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+

```bash
git clone https://github.com/bbjansen/simpleton.git
cd simpleton
swift build
swift run Simpleton
```

To iterate on a real, launchable app bundle:

```bash
bash scripts/e2e/make-app-bundle.sh debug
open .build/Simpleton.app
```

If repeated launches trigger Keychain prompts, create a stable local signing identity once and
re-sign after each build:

```bash
bash scripts/dev/make-dev-cert.sh   # one time
swift build && bash scripts/dev/sign-dev.sh
```

## Project layout

- `Sources/SimpletonCore/` — pure, UI-free logic (models, stores, parsers). Put testable logic here.
- `Sources/Simpleton/` — the AppKit + SwiftUI application.
- `Tests/CoreChecks/` — the no-Xcode test runner over `SimpletonCore`.
- `scripts/dev/`, `scripts/e2e/` — dev-signing and app-bundle / UI-smoke helpers.

Prefer adding logic to `SimpletonCore` so it can be covered by `CoreChecks` without a GUI.

## Before you open a pull request

1. **Build cleanly:**
   ```bash
   swift build
   ```
2. **Run the checks** (they must stay green):
   ```bash
   swift run CoreChecks
   ```
3. **Add checks** for any new logic in `SimpletonCore` — mirror the existing `*Checks.swift`
   files in `Tests/CoreChecks/` and register your suite in `Tests/CoreChecks/main.swift`.

CI runs `swift build` + `swift run CoreChecks` on macOS for every push and pull request.

## Branch & commit conventions

- Work on a feature branch — never commit directly to `main`.
  - `feature/…`, `fix/…`, `refactor/…`, `chore/…`, `docs/…`, `test/…`
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat(prefs): make the Preferences window resizable`
  - `fix(session): restore nested split layouts exactly`
  - `test(core): add SSH config parser checks`
- Keep commits focused and messages descriptive (what changed and why).

## Reporting bugs & requesting features

Please use the issue templates:

- 🐞 **Bug report** — steps to reproduce, expected vs. actual, macOS version.
- 💡 **Feature request** — the problem you're trying to solve and your proposed idea.

## Code of conduct

Be respectful and constructive. Assume good intent, and keep discussions focused on the work.
