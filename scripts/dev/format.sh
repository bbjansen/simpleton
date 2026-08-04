#!/usr/bin/env bash
# format.sh — format all Swift sources with swift-format (matches the CI "Format check").
#
# Usage:
#   scripts/dev/format.sh          # format in place
#   scripts/dev/format.sh --check  # report violations without changing files (like CI)
set -euo pipefail
cd "$(dirname "$0")/../.."

PATHS=(Sources Tests)

if [[ "${1:-}" == "--check" ]]; then
  swift format lint --recursive --parallel --strict "${PATHS[@]}"
  echo "Formatting OK."
else
  swift format --in-place --recursive --parallel "${PATHS[@]}"
  echo "Formatted ${PATHS[*]}. Verify with: scripts/dev/format.sh --check"
fi
