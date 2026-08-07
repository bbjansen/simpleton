#!/bin/bash
# Headless end-to-end check for Workspaces.
#
# Launches the app with SIMPLETON_WORKSPACE_E2E set, which (see AppDelegate.runWorkspaceE2E) splits
# the launch window into two panes, saves it as a workspace via WorkspaceManager, reopens it through
# SessionCoordinator, and asserts a fresh window came back with the two-pane split at the saved size.
# The run is fully isolated in a temp support dir (no onboarding, no saved session, no user data).
#
# Prints the SIMP-WSE2E RESULT line and exits 0 on PASS, 1 on FAIL.
set -euo pipefail
WT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$WT"

swift build >/dev/null 2>&1
scripts/e2e/make-app-bundle.sh debug >/dev/null 2>&1
BIN="$WT/.build/Simpleton.app/Contents/MacOS/Simpleton"

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
sleep 1

TMP="$(mktemp -d)"
touch "$TMP/.onboarding-done"   # skip the onboarding wizard
LOG="$(mktemp)"

SIMPLETON_SUPPORT_DIR="$TMP" SIMPLETON_WORKSPACE_E2E=1 "$BIN" >"$LOG" 2>&1 &
for _ in $(seq 1 20); do
  sleep 1
  grep -q "SIMP-WSE2E RESULT" "$LOG" && break
done

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
rm -rf "$TMP"

RESULT="$(grep "SIMP-WSE2E RESULT" "$LOG" | sed -E 's/.*SIMP-WSE2E/SIMP-WSE2E/' || true)"
rm -f "$LOG"
echo "${RESULT:-SIMP-WSE2E RESULT FAIL: no result (app did not report)}"

if echo "$RESULT" | grep -q "RESULT PASS"; then
  echo "workspace e2e: PASS"
  exit 0
else
  echo "workspace e2e: FAIL"
  exit 1
fi
