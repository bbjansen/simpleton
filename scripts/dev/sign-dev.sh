#!/usr/bin/env bash
# Sign the dev build with the stable "Simpleton Dev" identity so macOS Keychain
# "always allow" grants persist across rebuilds. Run this after every `swift build`.
#
# First-time setup: scripts/dev/make-dev-cert.sh
# Override the identity with SIMPLETON_SIGN_IDENTITY if you use a real cert.
set -euo pipefail

IDENTITY="${SIMPLETON_SIGN_IDENTITY:-Simpleton Dev}"
BIN="${1:-.build/debug/Simpleton}"

[ -x "$BIN" ] || { echo "no binary at $BIN — run: swift build"; exit 1; }
if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
  echo "code-signing identity '$IDENTITY' not found — run scripts/dev/make-dev-cert.sh first"
  exit 1
fi

# Stable --identifier keeps the designated requirement (and thus the Keychain ACL) constant.
codesign --force --sign "$IDENTITY" --identifier com.simpleton.terminal "$BIN"
echo "signed $BIN:"
codesign -dv "$BIN" 2>&1 | grep -E "Identifier|Authority" || true
