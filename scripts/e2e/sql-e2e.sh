#!/bin/bash
# Headless end-to-end check for the SQL client's connect/load flow.
#
# Launches the app with SIMPLETON_SQL_E2E set, which (see AppDelegate.runSQLPanelE2E) seeds a
# populated SQLite DB + a connection, drives SQLPanelModel's add flow (saveConnection), and asserts
# it auto-connects and loads the table — logging one "SIMP-SQLE2E RESULT PASS/FAIL …" line. The run
# is isolated in a temp support dir (no onboarding, no user data).
#
# Prints the SIMP-SQLE2E RESULT line and exits 0 on PASS, 1 on FAIL.
set -euo pipefail
WT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$WT"

swift build >/dev/null 2>&1
scripts/e2e/make-app-bundle.sh debug >/dev/null 2>&1
BIN="$WT/.build/Simpleton.app/Contents/MacOS/Simpleton"

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
sleep 1

TMP="$(mktemp -d)"
touch "$TMP/.onboarding-done"
LOG="$(mktemp)"

SIMPLETON_SUPPORT_DIR="$TMP" SIMPLETON_SQL_E2E=1 "$BIN" >"$LOG" 2>&1 &
for _ in $(seq 1 20); do
  sleep 1
  grep -q "SIMP-SQLE2E RESULT" "$LOG" && break
done

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
rm -rf "$TMP"

RESULT="$(grep "SIMP-SQLE2E RESULT" "$LOG" | sed -E 's/.*SIMP-SQLE2E/SIMP-SQLE2E/' || true)"
rm -f "$LOG"
echo "${RESULT:-SIMP-SQLE2E RESULT FAIL: no result (app did not report)}"

if echo "$RESULT" | grep -q "RESULT PASS"; then
  echo "sql e2e: PASS"
  exit 0
else
  echo "sql e2e: FAIL"
  exit 1
fi
