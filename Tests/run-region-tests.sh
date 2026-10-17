#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/topit-region-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc Topit/Supports/RegionGeometry.swift Tests/RegionGeometryTests.swift -o "$test_dir/geometry"
"$test_dir/geometry"
xcrun swiftc Topit/Supports/RegionGeometry.swift Topit/Supports/RegionCaptureSession.swift Tests/RegionTestSupport.swift Tests/RegionFrameTests.swift -o "$test_dir/frames"
"$test_dir/frames"
