#!/usr/bin/env python3
"""Build a signed Topit update. Ad-hoc signing is deliberately unsupported."""
import argparse
import ctypes
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

from topit_update import create_package, stable_requirement, verify

ROOT = Path(__file__).resolve().parent.parent


def keychain_is_unlocked(path):
    """Read keychain status without triggering an authentication dialog."""
    security = ctypes.CDLL('/System/Library/Frameworks/Security.framework/Security')
    foundation = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    security.SecKeychainOpen.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    security.SecKeychainOpen.restype = ctypes.c_int32
    security.SecKeychainGetStatus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    security.SecKeychainGetStatus.restype = ctypes.c_int32
    foundation.CFRelease.argtypes = [ctypes.c_void_p]
    keychain = ctypes.c_void_p()
    if security.SecKeychainOpen(str(path).encode(), ctypes.byref(keychain)) != 0:
        return False
    try:
        status = ctypes.c_uint32()
        return security.SecKeychainGetStatus(keychain, ctypes.byref(status)) == 0 and bool(status.value & 1)
    finally:
        foundation.CFRelease(keychain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'Config/signing.local.json')
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--base', type=Path, default=Path('/Applications/Topit.app'))
    parser.add_argument('--archive', type=Path, help='Also archive the same signed app for a public release')
    parser.add_argument('--source-revision', help='Embed the clean source commit in the signed Info.plist')
    parser.add_argument('--migrate-signer', action='store_true', help='First certificate-signed migration only; may require one last grant')
    parser.add_argument('--prepare-only', action='store_true', help='Build without accessing the signing key or creating an installable package')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+(?:\.\d+){1,2}', args.version) or args.build < 1:
        raise ValueError('Invalid version or build number')
    if args.source_revision and not re.fullmatch(r'[0-9a-f]{40}', args.source_revision):
        raise ValueError('Invalid source commit')
    if args.archive and args.archive.exists():
        raise FileExistsError(args.archive)
    config = json.loads(args.config.read_text())
    identity = config['identity_sha1'].upper()
    requirement = stable_requirement(identity)
    keychain = Path(config['keychain']).expanduser().resolve()
    if not keychain.is_file():
        raise ValueError('Configured signing keychain is missing')
    derived = ROOT.parent / 'update-build'
    subprocess.run([
        'xcodebuild', '-project', str(ROOT / 'Topit.xcodeproj'), '-scheme', 'Topit',
        '-configuration', 'Release', '-derivedDataPath', str(derived),
        'CODE_SIGNING_ALLOWED=NO', 'DEVELOPMENT_TEAM=',
        f'MARKETING_VERSION={args.version}', f'CURRENT_PROJECT_VERSION={args.build}', 'build'
    ], cwd=ROOT, check=True)
    app = derived / 'Build/Products/Release/Topit.app'
    if args.prepare_only:
        print(json.dumps({'prepared_unsigned_app': str(app), 'installed_app_changed': False}))
        return
    if args.source_revision:
        info_path = app / 'Contents/Info.plist'
        with info_path.open('rb') as stream:
            info = plistlib.load(stream)
        info['TopitSourceRevision'] = args.source_revision
        with info_path.open('wb') as stream:
            plistlib.dump(info, stream)
    if not keychain_is_unlocked(keychain):
        # The UI and legacy SecKeychainGetStatus can disagree across processes.
        # Actual certificate signing is authoritative, with a bounded timeout.
        print('Keychain status preflight did not report unlocked; attempting fixed-certificate signing with a timeout.', file=sys.stderr)
    subprocess.run([
        '/usr/bin/codesign', '--force', '--sign', identity, '--keychain', str(keychain),
        '--options', 'runtime', '--timestamp=none', '--entitlements', str(ROOT / 'Topit/Topit.entitlements'),
        '--requirements', '=designated => ' + requirement, str(app)
    ], check=True, timeout=15)
    verify(app, requirement)
    create_package(args.base, app, args.output, identity if args.migrate_signer else None)
    if args.archive:
        args.archive.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(args.archive)], check=True)
    print(json.dumps({'package': str(args.output.resolve()), 'signer_sha1': identity, 'installed_app_changed': False}))
    # A build product is never launched. Keep only the update package after packaging succeeds.
    shutil.rmtree(app)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print('Build update failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
