#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "Building SwiftHTTPie CLI..."
swift build > /dev/null

echo "Running SwiftHTTPie smoke test..."
if swift run SwiftHTTPie --help > /dev/null; then
  echo "Smoke test passed."
else
  echo "Smoke test failed." >&2
  exit 1
fi
