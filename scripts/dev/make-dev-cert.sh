#!/usr/bin/env bash
# One-time setup: create a self-signed code-signing identity so macOS Keychain
# "always allow" grants PERSIST across rebuilds.
#
# Why: an unsigned (or ad-hoc-signed) binary presents a different code identity on
# every `swift build`, so a Keychain ACL you approved last time never matches and
# you get re-prompted for the password every launch. Signing each build with one
# stable self-signed cert fixes that.
#
# After running this once, sign each build with scripts/dev/sign-dev.sh.
# The cert is self-signed (not Gatekeeper-trusted) — that's fine; we only need a
# stable identity for the Keychain ACL, not distribution trust.
set -euo pipefail

NAME="${1:-Simpleton Dev}"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "code-signing identity '$NAME' already exists — nothing to do"
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT   # holds private key material — deleted on exit
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -config "$TMP/cert.cnf"

# Ephemeral p12 password — the p12 is imported then deleted, so nothing sensitive persists.
P12PASS=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/dev.p12" -passout "pass:$P12PASS"

# -A: allow codesign to use the key without a per-use prompt.
security import "$TMP/dev.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$P12PASS" -A

# Modern macOS (10.12+) gates private-key access behind a PARTITION LIST that is separate from the
# ACL — so `-A` alone is NOT enough; codesign still prompts for the login password on every build.
# Add codesign (and apple tools) to the partition list so signing is silent from here on. This
# prompts ONCE for your login password.
echo "Adding codesign to the key partition list (enter your macOS login password if asked)…"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  "$HOME/Library/Keychains/login.keychain-db" >/dev/null

echo "created code-signing identity '$NAME':"
security find-identity -p codesigning | grep "$NAME" || true
