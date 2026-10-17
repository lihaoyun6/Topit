#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/topit-input-regressions.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -c Tests/NSExceptionCatcher.m -o "$test_dir/exceptions.o"
xcrun swiftc -import-objc-header Tests/NSExceptionCatcher.h Topit/Supports/SelectionEventPolicy.swift Tests/SelectionEventTests.swift "$test_dir/exceptions.o" -o "$test_dir/selection"
"$test_dir/selection"
xcrun swiftc -import-objc-header Tests/NSExceptionCatcher.h Topit/Supports/RegionEventFactory.swift Tests/RegionEventFactoryTests.swift "$test_dir/exceptions.o" -o "$test_dir/routing"
"$test_dir/routing"
xcrun swiftc Topit/Supports/RegionFocusHandoff.swift Tests/RegionFocusHandoffTests.swift -o "$test_dir/focus"
"$test_dir/focus"
xcrun swiftc Topit/Supports/RegionFocusSession.swift Tests/RegionFocusSessionTests.swift -o "$test_dir/focus-session"
"$test_dir/focus-session"
xcrun swiftc Topit/Supports/RegionPanel.swift Tests/RegionPanelFocusTests.swift -o "$test_dir/panel-focus"
"$test_dir/panel-focus"
xcrun swiftc Topit/Supports/RegionAutoHidePolicy.swift Tests/RegionAutoHideTests.swift -o "$test_dir/auto-hide"
"$test_dir/auto-hide"
xcrun swiftc Topit/Supports/ShortcutPreferences.swift Tests/ShortcutPreferencesTests.swift -o "$test_dir/shortcuts"
"$test_dir/shortcuts"
