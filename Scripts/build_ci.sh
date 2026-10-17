#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
topit_ci_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
topit_ci_derived="$topit_ci_root/topit-ci-build"
xcodebuild -version
xcodebuild -project Topit.xcodeproj -scheme Topit -configuration Release \
  -derivedDataPath "$topit_ci_derived" -destination 'generic/platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
  build > "$topit_ci_root/topit-build.log" 2>&1 || { tail -100 "$topit_ci_root/topit-build.log"; exit 1; }
python3 - "$topit_ci_derived/Build/Products/Release/Topit.app" <<'PY'
import json, plistlib, subprocess, sys
from pathlib import Path
app = Path(sys.argv[1])
config = json.loads(Path('Config/release.json').read_text())
with (app / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundleIdentifier'] == 'com.lihaoyun6.Topit'
assert info['CFBundleShortVersionString'] == config['version']
assert str(info['CFBundleVersion']) == str(config['build'])
architectures = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/Topit')], text=True).split()
assert set(architectures) == {'arm64', 'x86_64'}, architectures
print('Universal Release compilation verified; build product was not launched or published.')
PY
