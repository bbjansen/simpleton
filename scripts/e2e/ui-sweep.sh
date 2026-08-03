#!/usr/bin/env bash
# ui-sweep.sh — exercise Simpleton's menu commands via the macOS accessibility API
# and detect crashes. No Xcode required.
#
# For each command: click it, wait, then verify the process is still alive and no
# fatal error was logged. Screenshots each passing state. On a crash it records the
# culprit + fatal line and relaunches so a single run surfaces multiple bugs.
#
# Requires: Accessibility permission for the controlling terminal. Screen Recording
# for screenshots. Drives the real UI, so it takes over the screen while running.
set -uo pipefail

APP="Simpleton"
BIN="${BIN:-.build/debug/Simpleton}"
LOG="/tmp/simpleton-sweep.log"
SHOTS="/tmp/simpleton-sweep-shots"
WINID_SWIFT="${WINID_SWIFT:-scripts/e2e/window-id.swift}"
mkdir -p "$SHOTS"; rm -f "$SHOTS"/*.png

se() { osascript -e "tell application \"System Events\" to tell process \"$APP\" $1" 2>&1; }
front() { osascript -e "tell application \"System Events\" to tell process \"$APP\"
  set frontmost to true
  try
    perform action \"AXRaise\" of (first window whose subrole is \"AXStandardWindow\")
  end try" 2>/dev/null; }
alive() { pgrep -x "$APP" >/dev/null 2>&1 && ! grep -q "Fatal error" "$LOG"; }
wincount() { osascript -e "tell application \"System Events\" to tell process \"$APP\" to return (count of windows)" 2>/dev/null || echo "?"; }

# Dismiss any startup dialogs (Sparkle "Unable to Check For Updates" OK, restore
# Start Fresh, etc.) until none remain, so the terminal window is in front.
dismiss_dialogs() {
  local tries b clicked
  for tries in 1 2 3 4; do
    clicked=0
    for b in "OK" "Start Fresh" "Cancel" "Close"; do
      if osascript -e "tell application \"System Events\" to tell process \"$APP\" to click (first button of window 1 whose name starts with \"$b\")" 2>/dev/null; then clicked=1; sleep 0.8; break; fi
    done
    [ "$clicked" = 0 ] && break
  done
}

launch() {
  pkill -x "$APP" 2>/dev/null; sleep 1
  : > "$LOG"
  "$BIN" >"$LOG" 2>&1 &
  sleep 3
  dismiss_dialogs
  front
}

esc() { front; osascript -e 'tell application "System Events" to key code 53' 2>/dev/null; sleep 0.5; }

shot() { # $1 label — capture the largest Simpleton window by CG window id (occlusion-independent)
  local wid
  wid=$(swift "$WINID_SWIFT" "$APP" 2>/dev/null | head -1 | cut -f1)
  [ -n "$wid" ] && screencapture -x -l"$wid" "$SHOTS/$1.png" 2>/dev/null
}

click_item() { # $1 menu, $2 name-prefix (robust to trailing …/...)
  se "to click (first menu item of menu 1 of menu bar item \"$1\" of menu bar 1 whose name starts with \"$2\")"
}

# menu | item-prefix | kind(safe|modal)
ACTIONS=(
  "File|New Tab|safe"
  "Split|Split Right|safe"
  "Split|Split Down|safe"
  "SSH|Toggle Sidebar|safe"
  "View|Increase Font Size|safe"
  "View|Decrease Font Size|safe"
  "Edit|Clear Terminal|safe"
  "AI|AI Chat|modal"
  "Help|Command Palette|modal"
  "Edit|Find|modal"
  "Split|Pick Layout|modal"
  "SSH|Quick Connect|modal"
  "File|New Connection|modal"
  "AI|Run Skill|modal"
  "Window|Save Workspace|modal"
  "File|New Window|safe"
)

echo "=== Simpleton UI sweep ==="
launch
if ! alive; then echo "LAUNCH FAILED:"; grep "Fatal error" "$LOG" | head -1; exit 1; fi
echo "launch OK (windows=$(wincount))"; echo ""

crashes=0; passes=0
for entry in "${ACTIONS[@]}"; do
  IFS='|' read -r menu item kind <<< "$entry"
  label="$(echo "${menu}_${item}" | tr ' ' '_')"
  click_item "$menu" "$item" >/dev/null 2>&1
  sleep 1.5
  if alive; then
    passes=$((passes+1))
    printf "PASS  [%-5s] %-8s > %-16s  windows=%s\n" "$kind" "$menu" "$item" "$(wincount)"
    shot "$label"
    [ "$kind" = "modal" ] && esc
  else
    crashes=$((crashes+1))
    printf "CRASH [%-5s] %-8s > %-16s  :: %s\n" "$kind" "$menu" "$item" "$(grep 'Fatal error' "$LOG" | tail -1)"
    launch
    alive || { echo "  relaunch failed — aborting"; break; }
  fi
done

echo ""
echo "=== sweep complete: $passes passed, $crashes crashed ==="
echo "screenshots: $SHOTS"
pkill -x "$APP" 2>/dev/null
exit 0
