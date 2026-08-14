#!/bin/bash
# Headless end-to-end check for panel-profile + preferences persistence.
#
# Launches the app with SIMPLETON_PROFILES_E2E set, which (see AppDelegate.runProfilesE2E) drives a
# real PanelRegistry against an isolated temp profiles dir: it activates a non-default profile, edits
# a built-in default (appends a panel id + changes leftWidth), sets a width, and persists. It then
# builds a SECOND PanelRegistry on the same dir and loadProfiles() (a simulated relaunch) and asserts
# the active selection stuck, the built-in edit + width restored, a user profile survived, and the
# seeded Developer profile ships s3/sftp/amqp. Logs one "SIMP-PROFILE RESULT PASS/FAIL …" line. The
# run is isolated in a temp support dir (no onboarding, no user data).
#
# Prints the SIMP-PROFILE RESULT line and exits 0 on PASS, 1 on FAIL.
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

SIMPLETON_SUPPORT_DIR="$TMP" SIMPLETON_PROFILES_E2E=1 "$BIN" >"$LOG" 2>&1 &
for _ in $(seq 1 20); do
  sleep 1
  grep -q "SIMP-PROFILE RESULT" "$LOG" && break
done

pkill -f "Simpleton.app/Contents/MacOS/Simpleton" 2>/dev/null || true
rm -rf "$TMP"

RESULT="$(grep "SIMP-PROFILE RESULT" "$LOG" | sed -E 's/.*SIMP-PROFILE/SIMP-PROFILE/' || true)"
rm -f "$LOG"
echo "${RESULT:-SIMP-PROFILE RESULT FAIL: no result (app did not report)}"

if echo "$RESULT" | grep -q "RESULT PASS"; then
  echo "profiles e2e: PASS"
  exit 0
else
  echo "profiles e2e: FAIL"
  exit 1
fi
