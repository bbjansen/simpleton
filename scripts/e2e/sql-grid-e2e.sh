#!/bin/bash
# Headless check for the SQL results grid's FROZEN FIRST DATA COLUMN.
#
# Launches the app with SIMPLETON_SQL_GRID_E2E set, which (see AppDelegate.runSQLGridE2E) mounts the
# real SQLDataGrid in an offscreen window with a seeded 40-row result and asserts observable facts:
# the frozen pane exists and is pinned at the left edge, the first data column is collapsed in the
# main table (its cells live in the pane), the main table still renders its other data, and the pane
# stays present + aligned through a vertical scroll. Logs one "SIMP-SQLGRID RESULT PASS/FAIL …" line.
#
# Prints the SIMP-SQLGRID RESULT line and exits 0 on PASS, 1 on FAIL.
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

SIMPLETON_SUPPORT_DIR="$TMP" SIMPLETON_SQL_GRID_E2E=1 "$BIN" >"$LOG" 2>&1 &
for _ in $(seq 1 20); do
  sleep 1
  grep -q "SIMP-SQLGRID RESULT" "$LOG" && break
done

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
rm -rf "$TMP"

RESULT="$(grep "SIMP-SQLGRID RESULT" "$LOG" | sed -E 's/.*SIMP-SQLGRID/SIMP-SQLGRID/' || true)"
rm -f "$LOG"
echo "${RESULT:-SIMP-SQLGRID RESULT FAIL: no result (app did not report)}"

if echo "$RESULT" | grep -q "RESULT PASS"; then
  echo "sql grid e2e: PASS"
  exit 0
else
  echo "sql grid e2e: FAIL"
  exit 1
fi
