#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Tests/run-input-regressions.sh
bash Tests/run-region-tests.sh
python3 Tests/UpdateProtocolTests.py
python3 Tests/ReleaseAssetsTests.py
plutil -lint Topit/zh-Hans.lproj/Localizable.strings Topit/zh-Hant.lproj/Localizable.strings Topit.xcodeproj/project.pbxproj
git diff --check
