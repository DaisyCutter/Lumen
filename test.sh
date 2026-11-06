#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lumen-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" Lumen/Models.swift Lumen/Collector.swift Tests/SmokeTests.swift -o "$TEMP_DIR/smoke"
"$TEMP_DIR/smoke"
