#!/usr/bin/env bash
# publish-lane.sh — sign, (optionally) notarize, EdDSA-sign and publish ONE release lane.
#
# The release build produces two artifacts from a single xcodebuild: a universal .app and an
# arm64-only .app, each with its own Sparkle feed. This script packages and publishes one of
# them, so the logic lives in exactly one place. It self-gates on the presence of secrets (same
# decoupled gating as the workflow): Developer ID signing + notarization need Apple creds, EdDSA
# signing needs the Sparkle key, publishing needs the Sparkle key + Cloudflare creds.
#
# Required env:
#   LANE_LABEL        human label for logs (e.g. "universal" or "arm64")
#   LANE_APP          path to the assembled .app
#   LANE_ZIP          output zip path (also the attached/published artifact; basename is its URL name)
#   LANE_FEED_URL     this lane's appcast URL, "<public-base>/<appcast-file>"
#   LANE_APPCAST_OBJ  remote object name for the appcast (e.g. "appcast.xml" / "appcast-arm64.xml")
#   SHORT BUILD       marketing version / monotonic build number
#   NOTARIZE SPARKLE PUBLISH   gate flags ("true"/"false")
#   RUNNER_TEMP       scratch dir
# Required when the matching gate is true:
#   notarize: SIGN_IDENTITY, ASC_API_KEY_P8_BASE64, ASC_KEY_ID, ASC_ISSUER_ID
#   sparkle:  SPARKLE_PRIVATE_KEY
#   publish:  CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, R2_BUCKET
set -euo pipefail

: "${LANE_LABEL:?}" "${LANE_APP:?}" "${LANE_ZIP:?}" "${SHORT:?}" "${BUILD:?}" "${RUNNER_TEMP:?}"
NOTARIZE="${NOTARIZE:-false}"; SPARKLE="${SPARKLE:-false}"; PUBLISH="${PUBLISH:-false}"
APP="$LANE_APP"; ZIP="$LANE_ZIP"
echo "::group::[$LANE_LABEL] package & publish (notarize=$NOTARIZE sparkle=$SPARKLE publish=$PUBLISH)"

# --- Developer ID sign (hardened runtime, inside-out) --------------------------------------------
if [ "$NOTARIZE" = "true" ]; then
  : "${SIGN_IDENTITY:?}"
  FW="$APP/Contents/MacOS/Sparkle.framework" # this app embeds Sparkle under MacOS/
  FWV="$FW/Versions/B"                        # Sparkle 2.x layout
  sign() { codesign -f -s "$SIGN_IDENTITY" -o runtime --timestamp "$@"; }
  if [ -d "$FWV/XPCServices/Installer.xpc" ]; then sign "$FWV/XPCServices/Installer.xpc"; fi
  if [ -d "$FWV/XPCServices/Downloader.xpc" ]; then
    codesign -f -s "$SIGN_IDENTITY" -o runtime --timestamp \
      --preserve-metadata=entitlements "$FWV/XPCServices/Downloader.xpc"
  fi
  if [ -e "$FWV/Autoupdate" ]; then sign "$FWV/Autoupdate"; fi
  if [ -d "$FWV/Updater.app" ]; then sign "$FWV/Updater.app"; fi
  if [ -d "$FW" ]; then sign "$FW"; fi
  sign "$APP/Contents/MacOS/Simpleton"
  sign "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

# --- Notarize + staple, then package -------------------------------------------------------------
if [ "$NOTARIZE" = "true" ]; then
  : "${ASC_API_KEY_P8_BASE64:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
  KEY="$RUNNER_TEMP/asc.p8"
  printf '%s' "$ASC_API_KEY_P8_BASE64" | base64 --decode > "$KEY"
  ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize-${LANE_LABEL}.zip"
  xcrun notarytool submit "$RUNNER_TEMP/notarize-${LANE_LABEL}.zip" \
    --key "$KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -t exec -vv "$APP" || true
fi
ditto -c -k --keepParent "$APP" "$ZIP"
echo "[$LANE_LABEL] packaged $ZIP ($(du -h "$ZIP" | cut -f1))"

# --- Sparkle EdDSA sign --------------------------------------------------------------------------
ED=""; LEN=""
if [ "$SPARKLE" = "true" ]; then
  : "${SPARKLE_PRIVATE_KEY:?}"
  # Use ONLY the sign_update shipped inside Sparkle's SPM artifact (integrity pinned via
  # Package.resolved's checksum). xcodebuild extracts it under DerivedData/SourcePackages.
  SIGN_UPDATE="$(find "$RUNNER_TEMP/dd/SourcePackages" .build/artifacts -path '*/Sparkle/bin/sign_update' 2>/dev/null | head -n1 || true)"
  if [ -z "$SIGN_UPDATE" ]; then
    echo "::error::sign_update not found (Sparkle SPM artifact). Refusing to fetch an unverified tool." >&2
    exit 1
  fi
  SIG_OUT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
  echo "$SIG_OUT"
  ED="$(printf '%s' "$SIG_OUT" | sed -E 's/.*edSignature="([^"]+)".*/\1/')"
  LEN="$(printf '%s' "$SIG_OUT" | sed -E 's/.*length="([0-9]+)".*/\1/')"
fi

# --- Publish zip + sidecar + appcast to R2 -------------------------------------------------------
if [ "$PUBLISH" = "true" ]; then
  : "${CLOUDFLARE_API_TOKEN:?}" "${CLOUDFLARE_ACCOUNT_ID:?}" "${R2_BUCKET:?}"
  : "${LANE_FEED_URL:?}" "${LANE_APPCAST_OBJ:?}"
  FILE="$(basename "$ZIP")"
  SIDE="$RUNNER_TEMP/${FILE%.zip}.json"
  APPCAST="$RUNNER_TEMP/${LANE_APPCAST_OBJ}"
  PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
  BASE="${LANE_FEED_URL%/"${LANE_APPCAST_OBJ}"}"
  if [ -z "$BASE" ] || [ "$BASE" = "$LANE_FEED_URL" ]; then
    echo "::error::LANE_FEED_URL ($LANE_FEED_URL) must end in /$LANE_APPCAST_OBJ" >&2; exit 1
  fi
  ENCLOSURE="${BASE}/releases/${FILE}"
  # Sidecar JSON — the contract with services/update-server for a future Worker-served feed.
  jq -n \
    --arg version "$BUILD" --arg shortVersionString "$SHORT" --arg pubDate "$PUBDATE" \
    --arg edSignature "$ED" --argjson length "${LEN:-0}" --arg minimumSystemVersion "14.0" \
    '{version:$version, shortVersionString:$shortVersionString, pubDate:$pubDate, edSignature:$edSignature, length:$length, minimumSystemVersion:$minimumSystemVersion}' \
    > "$SIDE"
  # Static single-item appcast (latest release for this lane). base64 edSignature + URL contain
  # no XML-special characters, so no escaping is needed.
  {
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
    printf '%s\n' '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
    printf '%s\n' '  <channel>'
    printf '    <title>Simpleton (%s)</title>\n' "$LANE_LABEL"
    printf '%s\n' '    <item>'
    printf '      <title>%s</title>\n' "$SHORT"
    printf '      <pubDate>%s</pubDate>\n' "$PUBDATE"
    printf '      <sparkle:version>%s</sparkle:version>\n' "$BUILD"
    printf '      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$SHORT"
    printf '%s\n' '      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>'
    printf '      <enclosure url="%s" length="%s" type="application/octet-stream" sparkle:edSignature="%s" />\n' "$ENCLOSURE" "$LEN" "$ED"
    printf '%s\n' '    </item>'
    printf '%s\n' '  </channel>'
    printf '%s\n' '</rss>'
  } > "$APPCAST"
  cat "$APPCAST"
  wr() { npx --yes wrangler@4.153.0 r2 object put "$@"; }
  wr "${R2_BUCKET}/releases/${FILE}" --file "$ZIP" --remote --content-type application/zip
  wr "${R2_BUCKET}/releases/${FILE%.zip}.json" --file "$SIDE" --remote --content-type application/json
  wr "${R2_BUCKET}/${LANE_APPCAST_OBJ}" --file "$APPCAST" --remote --content-type application/xml
fi

echo "::endgroup::"
