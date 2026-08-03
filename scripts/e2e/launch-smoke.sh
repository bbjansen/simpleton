#!/usr/bin/env bash
# Launch smoke test for Simpleton.
# Verifies the app starts without crashing and presents at least one window.
#
# Usage: scripts/e2e/launch-smoke.sh [path-to-binary]
# Env:   WAIT_SECS (default 8) — how long to wait for a window.
#
# Exit 0 = PASS (process alive, no fatal error, >=1 window observed via accessibility).
# Exit 1 = FAIL (crash, early exit, or no window).
#
# Requires: Accessibility permission for the controlling terminal (System Events scripting).
set -uo pipefail

BIN="${1:-.build/debug/Simpleton}"
LOG="/tmp/simpleton-smoke.log"
WAIT_SECS="${WAIT_SECS:-8}"

echo "[smoke] binary: $BIN"
if [ ! -x "$BIN" ]; then
  echo "[smoke] FAIL: binary not found or not executable at $BIN"
  exit 1
fi

# Clean up any prior instance.
pkill -x Simpleton 2>/dev/null && sleep 1

: > "$LOG"
"$BIN" >"$LOG" 2>&1 &
APP_PID=$!
echo "[smoke] launched pid=$APP_PID, waiting up to ${WAIT_SECS}s for a window..."

for i in $(seq 1 "$WAIT_SECS"); do
  sleep 1

  if grep -q "Fatal error" "$LOG" 2>/dev/null; then
    echo "[smoke] FAIL: fatal error during launch:"
    grep "Fatal error" "$LOG" | head -3
    pkill -x Simpleton 2>/dev/null
    exit 1
  fi

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "[smoke] FAIL: process exited early (${i}s). Log tail:"
    tail -5 "$LOG"
    exit 1
  fi

  wincount=$(osascript -e 'tell application "System Events" to tell process "Simpleton" to return (count of windows)' 2>/dev/null || echo 0)
  wincount=${wincount:-0}
  if [ "$wincount" -ge 1 ] 2>/dev/null; then
    echo "[smoke] PASS: alive, no fatal error, windows=$wincount after ${i}s"
    echo "[smoke] window titles: $(osascript -e 'tell application "System Events" to tell process "Simpleton" to return name of windows' 2>/dev/null)"
    exit 0
  fi
done

echo "[smoke] FAIL: no window appeared within ${WAIT_SECS}s. Log tail:"
tail -8 "$LOG"
pkill -x Simpleton 2>/dev/null
exit 1
