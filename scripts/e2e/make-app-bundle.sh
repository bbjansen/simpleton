#!/usr/bin/env bash
# make-app-bundle.sh — assemble a runnable, signed Simpleton.app from an SPM build.
#
# A bare SPM executable does not activate reliably, cannot be screenshotted by window
# z-order, and breaks Sparkle. This wraps the built binary + SPM resource bundle + the
# dynamically-linked Sparkle.framework, disables Sparkle's auto update-check (there is
# no signed appcast for a dev build, so it would otherwise show an "Unable to Check For
# Updates" dialog on launch), and signs everything with the stable "Simpleton Dev"
# identity so it launches via `open` like a normal app (and Keychain grants stay
# consistent).
#
# Usage: scripts/e2e/make-app-bundle.sh [debug|release]   (default: debug)
# Output: .build/Simpleton.app
set -euo pipefail

CONFIG="${1:-debug}"
BINDIR=".build/${CONFIG}"
APP=".build/Simpleton.app"
BIN="${BINDIR}/Simpleton"
IDENTITY="${SIMPLETON_SIGN_IDENTITY:-Simpleton Dev}"

[ -x "$BIN" ] || { echo "no binary at $BIN — run: swift build ${CONFIG:+-c $CONFIG}"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Simpleton"

# SPM resource bundle(s) → Resources only (Bundle.module resolves via Bundle.main.resourceURL).
# Do NOT place them in MacOS/ — codesign --deep rejects resource bundles there.
shopt -s nullglob
for b in "${BINDIR}"/*.bundle; do
  ditto "$b" "$APP/Contents/Resources/$(basename "$b")"
done

# Embed Sparkle.framework next to the binary so the binary's existing @loader_path rpath
# finds it (dyld searches @loader_path = Contents/MacOS). Avoids install_name_tool.
SPARKLE="${BINDIR}/Sparkle.framework"   # note: BINDIR may be a symlink, so use the path directly
[ -d "$SPARKLE" ] && ditto "$SPARKLE" "$APP/Contents/MacOS/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Simpleton</string>
  <key>CFBundleIdentifier</key><string>com.simpleton.terminal</string>
  <key>CFBundleName</key><string>Simpleton</string>
  <key>CFBundleDisplayName</key><string>Simpleton</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Dev build: don't let Sparkle auto-check (no signed appcast exists). -->
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUFeedURL</key><string>https://example.invalid/appcast.xml</string>
</dict>
</plist>
PLIST

# Sign nested code first (Sparkle framework + its helpers), then the app, with the stable
# dev identity if present (else ad-hoc). Signing inner code before the outer bundle avoids
# --deep's ordering pitfalls.
SIGN_ID="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then SIGN_ID="$IDENTITY"; fi
if [ -d "$APP/Contents/MacOS/Sparkle.framework" ]; then
  find "$APP/Contents/MacOS/Sparkle.framework" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) -print0 2>/dev/null \
    | while IFS= read -r -d '' c; do codesign --force --sign "$SIGN_ID" "$c" >/dev/null 2>&1 || true; done
  codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/Sparkle.framework" >/dev/null 2>&1 || true
fi
codesign --force --sign "$SIGN_ID" --identifier com.simpleton.terminal "$APP/Contents/MacOS/Simpleton" >/dev/null 2>&1 || true
codesign --force --sign "$SIGN_ID" --identifier com.simpleton.terminal "$APP" 2>&1 | grep -v "replacing existing signature" || true

echo "built $APP (signed with '$SIGN_ID')"
