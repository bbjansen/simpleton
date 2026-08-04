#!/usr/bin/env bash
# ui-audit.sh — reliable visual audit of Simpleton's surfaces via the AX driver (no osascript).
# Requires a running Simpleton (ideally launched against a demo SIMPLETON_SUPPORT_DIR with fake data).
# Output: .build/ui-audit/*.png
set -euo pipefail
cd "$(dirname "$0")/../.."

AX=/tmp/axdriver
swiftc -O -o "$AX" scripts/e2e/axdriver.swift
OUT=.build/ui-audit
rm -rf "$OUT"
mkdir -p "$OUT"

PID=$(pgrep -x Simpleton | head -1 || true)
[ -z "${PID:-}" ] && { echo "Simpleton is not running"; exit 1; }
echo "Auditing Simpleton pid $PID → $OUT"

snap() { "$AX" shot "$PID" "$OUT/$1.png" "${2:-}" >/dev/null 2>&1 && echo "  ✓ $1" || echo "  ✗ $1"; }
press() { "$AX" press "$PID" "$1" >/dev/null 2>&1 || true; }
menu() { "$AX" menu "$PID" "$1" >/dev/null 2>&1 || true; }
key() { "$AX" key "$PID" "$@" >/dev/null 2>&1 || true; }
type() { "$AX" type "$PID" "$1" >/dev/null 2>&1 || true; }

"$AX" raise "$PID"; sleep 0.4
snap 01-home
type "echo hello && sw_vers -productName"; key 36; sleep 0.6; snap 02-terminal   # 36 = Return
press sparkles; sleep 0.8; snap 03-ai-panel;   press sparkles; sleep 0.4          # AI panel (right rail)
press clock;    sleep 0.8; snap 04-history;     press clock;    sleep 0.4          # History panel
press folder;   sleep 0.8; snap 05-files;       press folder;   sleep 0.4          # File browser panel
menu "Split Right"; sleep 0.8; snap 06-split-right
menu "New Tab";     sleep 0.9; snap 07-new-tab
menu "Settings…";   sleep 1.0; snap 08-settings "Preferences"

echo "Done — $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots in $OUT"
