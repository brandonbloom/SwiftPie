#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "Building SwiftPie CLI..."
swift build > /dev/null

echo "Running SwiftPie smoke test..."
if swift run spie --help > /dev/null; then
  echo "Smoke test passed."
else
  echo "Smoke test failed." >&2
  exit 1
fi

echo "Running PeerDemo smoke test..."
if swift run PeerDemo /get > /dev/null; then
  echo "PeerDemo smoke test passed."
else
  echo "PeerDemo smoke test failed." >&2
  exit 1
fi
