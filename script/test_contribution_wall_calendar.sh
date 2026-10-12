#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d /tmp/tokenstep-wall-calendar.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -parse-as-library \
  "$ROOT_DIR/TokenStepSwift/Sources/TokenStepSwift/Support/ContributionWallCalendar.swift" \
  "$ROOT_DIR/TokenStepSwift/Tests/Fixtures/ContributionWallCalendarFixture.swift" \
  -o "$BUILD_DIR/check"
"$BUILD_DIR/check"
