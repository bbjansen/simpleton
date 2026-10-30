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
# Where the built products live. Defaults to SwiftPM's .build/<config>, but the release pipeline builds
# with xcodebuild and points this at DerivedData/Build/Products/Release via SIMPLETON_BINDIR.
BINDIR="${SIMPLETON_BINDIR:-.build/${CONFIG}}"
# Output .app path. Defaults to .build/Simpleton.app; the release pipeline overrides it to build
# both a universal and an arm64 bundle in one run (SIMPLETON_APP_OUT).
APP="${SIMPLETON_APP_OUT:-.build/Simpleton.app}"
BIN="${BINDIR}/Simpleton"
IDENTITY="${SIMPLETON_SIGN_IDENTITY:-Simpleton Dev}"

[ -x "$BIN" ] || { echo "no binary at $BIN — run: swift build ${CONFIG:+-c $CONFIG}"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Simpleton"

# Strip debug + local symbols from the executable (release builds ship with -g and a bloated
# __LINKEDIT). Keeps the dSYM-less binary much smaller; harmless for a standalone app binary.
# Must run before signing — it invalidates any existing signature. (Opt out with SIMPLETON_NO_STRIP=1.)
if [ "${SIMPLETON_NO_STRIP:-0}" != "1" ]; then
  strip -S -x "$APP/Contents/MacOS/Simpleton"
fi

# SPM resource bundle(s) → Resources only (Bundle.module resolves via Bundle.main.resourceURL).
# Do NOT place them in MacOS/ — codesign --deep rejects resource bundles there.
shopt -s nullglob
for b in "${BINDIR}"/*.bundle; do
  ditto "$b" "$APP/Contents/Resources/$(basename "$b")"
done

# Embed Sparkle.framework next to the binary (Contents/MacOS). The binary links it as
# @rpath/Sparkle.framework, so dyld must have an rpath that resolves to this directory.
SPARKLE="${BINDIR}/Sparkle.framework"   # note: BINDIR may be a symlink, so use the path directly
[ -d "$SPARKLE" ] && ditto "$SPARKLE" "$APP/Contents/MacOS/Sparkle.framework"

# xcodebuild-built binaries carry only @executable_path/../lib (→ Contents/lib) as their
# relocatable rpath, so @rpath/Sparkle.framework misses the framework above and the app
# aborts at launch ("Library not loaded: @rpath/Sparkle.framework"). Add a plain
# @executable_path rpath (= Contents/MacOS) so dyld finds it. swift build binaries already
# resolve it; only add when the exact entry is absent (install_name_tool errors on a
# duplicate). Must run before signing — it invalidates any existing signature.
if [ -d "$APP/Contents/MacOS/Sparkle.framework" ]; then
  if ! otool -l "$APP/Contents/MacOS/Simpleton" | awk '/LC_RPATH/{f=1;next} f&&/ path /{print $2;f=0}' | grep -Fxq '@executable_path'; then
    install_name_tool -add_rpath @executable_path "$APP/Contents/MacOS/Simpleton"
  fi
fi

# Sparkle / versioning are env-driven so the release pipeline can bake in the real update
# feed, public key, auto-checks, and an incrementing build number — while a plain dev build
# keeps the old behavior (auto-checks off, placeholder feed, ad-hoc signed). Env vars:
#   SIMPLETON_SHORT_VERSION    marketing version  → CFBundleShortVersionString (default 0.1.1)
#   SIMPLETON_BUILD_VERSION    build number       → CFBundleVersion, MUST increment per release (default 1)
#   SIMPLETON_SU_FEED_URL      appcast URL        → SUFeedURL (default a placeholder)
#   SIMPLETON_SU_PUBLIC_ED_KEY Sparkle EdDSA pub  → SUPublicEDKey (omitted when empty)
#   SIMPLETON_SU_AUTO_CHECKS   "true" to enable background update checks (default false)
SHORT_VERSION="${SIMPLETON_SHORT_VERSION:-0.1.1}"
BUILD_VERSION="${SIMPLETON_BUILD_VERSION:-1}"
SU_FEED_URL="${SIMPLETON_SU_FEED_URL:-https://example.invalid/appcast.xml}"
SU_PUBLIC_ED_KEY="${SIMPLETON_SU_PUBLIC_ED_KEY:-}"
SU_AUTO_CHECKS="${SIMPLETON_SU_AUTO_CHECKS:-false}"

if [ "$SU_AUTO_CHECKS" = "true" ]; then
  SU_CHECK_KEYS="  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>"
else
  SU_CHECK_KEYS="  <!-- Dev build: don't let Sparkle auto-check (no signed appcast exists). -->
  <key>SUEnableAutomaticChecks</key><false/>"
fi
SU_KEY_LINE=""
[ -n "$SU_PUBLIC_ED_KEY" ] && SU_KEY_LINE="  <key>SUPublicEDKey</key><string>${SU_PUBLIC_ED_KEY}</string>"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Simpleton</string>
  <key>CFBundleIdentifier</key><string>com.simpleton.terminal</string>
  <key>CFBundleName</key><string>Simpleton</string>
  <key>CFBundleDisplayName</key><string>Simpleton</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>${SU_FEED_URL}</string>
${SU_CHECK_KEYS}
${SU_KEY_LINE}
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
