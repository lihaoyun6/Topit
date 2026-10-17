#!/usr/bin/env python3
"""Create and apply local, signed, incremental Topit updates. Never writes TCC."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import zipfile

BUNDLE_ID = 'com.lihaoyun6.Topit'
INSTALLED_APP = Path('/Applications/Topit.app')
FORMAT = 'topit.incremental.v1'


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, **kwargs)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def safe_path(value):
    if not isinstance(value, str) or '\\' in value:
        raise ValueError('Invalid package path')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'Contents':
        raise ValueError(f'Unsafe package path: {value!r}')
    if str(path) != value:
        raise ValueError(f'Noncanonical package path: {value!r}')
    return path


def inventory(app):
    result = {}
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise ValueError('This updater supports Topit bundles without symlinks: ' + str(path))
        if path.is_file():
            name = path.relative_to(app).as_posix()
            safe_path(name)
            result[name] = {'sha256': sha256(path), 'mode': stat.S_IMODE(path.stat().st_mode) & 0o777}
    return result


def tree_digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def app_info(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('The app is not Topit')
    return info


def designated_requirement(app):
    result = run('/usr/bin/codesign', '-d', '-r-', app)
    for line in (result.stdout + result.stderr).splitlines():
        line = line.lstrip('# ')
        if line.startswith('designated => '):
            return line.removeprefix('designated => ')
    raise ValueError('No designated code requirement found')


def verify(app, requirement=None):
    args = ['/usr/bin/codesign', '--verify', '--deep', '--strict']
    if requirement:
        args += ['-R', '=' + requirement]
    run(*args, app)


def stable_requirement(fingerprint):
    if not re.fullmatch(r'[0-9a-fA-F]{40}', fingerprint):
        raise ValueError('A certificate SHA-1 fingerprint (40 hexadecimal characters) is required')
    return f'identifier "{BUNDLE_ID}" and certificate leaf = H"{fingerprint.upper()}"'


def create_package(base, target, output, signer=None):
    base_info, target_info = app_info(base), app_info(target)
    verify(base)
    verify(target)
    base_req = designated_requirement(base)
    # For ordinary updates, cryptographically check the installed app's identity.
    # The first migration is explicit and pinned to a certificate, never to an identifier alone.
    requirement = stable_requirement(signer) if signer else base_req
    if not signer and 'cdhash' in base_req:
        raise ValueError('The installed app uses ad-hoc signing. First create an explicit stable-signer migration package.')
    verify(target, requirement)
    old, new = inventory(base), inventory(target)
    changed = sorted(name for name, value in new.items() if old.get(name) != value)
    removed = sorted(set(old) - set(new))
    if not changed and not removed:
        raise ValueError('There are no changes to package')
    manifest = {
        'format': FORMAT, 'bundle_id': BUNDLE_ID,
        'base_version': base_info['CFBundleShortVersionString'], 'base_build': base_info['CFBundleVersion'],
        'target_version': target_info['CFBundleShortVersionString'], 'target_build': target_info['CFBundleVersion'],
        'base_tree': tree_digest(old), 'target_tree': tree_digest(new),
        'files': new, 'changed': changed, 'removed': removed,
        'signer_migration': signer.upper() if signer else None,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation: never overwrite a previous update package.
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2))
        for name in changed:
            archive.write(target / name, 'payload/' + name)
    return manifest


def validate_manifest(manifest):
    if manifest.get('format') != FORMAT or manifest.get('bundle_id') != BUNDLE_ID:
        raise ValueError('Unsupported update package')
    files = manifest['files']
    for name, meta in files.items():
        safe_path(name)
        if not re.fullmatch(r'[0-9a-f]{64}', meta['sha256']):
            raise ValueError('Invalid file digest')
        if not isinstance(meta['mode'], int) or not 0 <= meta['mode'] <= 0o777 or meta['mode'] & 0o022:
            raise ValueError('Invalid file permissions')
    changed, removed = manifest['changed'], manifest['removed']
    if len(set(changed)) != len(changed) or len(set(removed)) != len(removed):
        raise ValueError('Duplicate paths in update')
    for name in changed:
        safe_path(name)
        if name not in files:
            raise ValueError('Missing target metadata')
    for name in removed:
        safe_path(name)
        if name in files:
            raise ValueError('Removed file still present in target metadata')


def stage_update(package, app, stage, migration_signer=None):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names):
            raise ValueError('Duplicate archive entries')
        manifest = json.loads(archive.read('manifest.json'))
        validate_manifest(manifest)
        expected = {'manifest.json'} | {'payload/' + name for name in manifest['changed']}
        if set(names) != expected:
            raise ValueError('Unexpected or missing archive entries')
        current = inventory(app)
        if tree_digest(current) != manifest['base_tree']:
            raise ValueError('This update does not match the installed version. The app has been left unchanged.')
        for item in archive.infolist():
            if stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError('Symlinks are not permitted in an update archive')
        shutil.copytree(app, stage)
        for name in manifest['removed']:
            (stage / name).unlink()
        for name in manifest['changed']:
            destination = stage / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open('payload/' + name) as source, destination.open('wb') as target:
                shutil.copyfileobj(source, target)
            os.chmod(destination, manifest['files'][name]['mode'])
    if tree_digest(inventory(stage)) != manifest['target_tree']:
        raise ValueError('The staged app does not match the target digest')
    info = app_info(stage)
    if str(info['CFBundleVersion']) != str(manifest['target_build']) or info['CFBundleShortVersionString'] != manifest['target_version']:
        raise ValueError('The staged version does not match the manifest')
    if not os.access(stage / 'Contents/MacOS/Topit', os.X_OK):
        raise ValueError('The target executable is not executable')
    verify(stage)
    if manifest['signer_migration']:
        if not migration_signer or manifest['signer_migration'] != migration_signer.upper():
            raise ValueError('First signer migration requires explicit --migrate-signer CERTIFICATE_SHA1. No app files changed.')
        verify(stage, stable_requirement(migration_signer))
    else:
        if migration_signer:
            raise ValueError('Signer migration was requested for a normal update')
        requirement = designated_requirement(app)
        if 'cdhash' in requirement:
            raise ValueError('Normal updates require a stable certificate signature')
        verify(stage, requirement)
    return manifest


def installed_pids(app):
    executable = str(app / 'Contents/MacOS/Topit')
    result = run('/bin/ps', '-axo', 'pid=,comm=')
    return [int(fields[0]) for line in result.stdout.splitlines()
            if len(fields := line.strip().split(None, 1)) == 2 and fields[1] == executable]


def stop_installed(app):
    pids = installed_pids(app)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 5
    while any(pid in installed_pids(app) for pid in pids):
        if time.monotonic() > deadline:
            raise RuntimeError('Topit did not quit. Installation stopped without changing the app.')
        time.sleep(0.1)


def apply_package(args):
    app = args.app.resolve()
    if app != INSTALLED_APP:
        raise ValueError('Installations are restricted to /Applications/Topit.app')
    app_info(app)
    verify(app)
    # Stage on the same volume, so the final rename is atomic per directory.
    with tempfile.TemporaryDirectory(prefix='.topit-update-', dir=app.parent) as temporary:
        temporary = Path(temporary)
        stage = temporary / 'Topit.app'
        manifest = stage_update(args.package, app, stage, args.migrate_signer)
        if args.check:
            print(json.dumps({'verified': True, 'will_install': manifest['target_version'], 'migration': bool(manifest['signer_migration'])}))
            return
        backup_root = args.backups.expanduser().resolve()
        backup_root.mkdir(parents=True, exist_ok=True)
        timestamp = time.strftime('%Y%m%d-%H%M%S')
        backup = backup_root / f'Topit-{manifest["base_version"]}-{timestamp}.zip'
        if backup.exists():
            raise FileExistsError(backup)
        run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, backup)
        run('/usr/bin/unzip', '-tq', backup)
        if tree_digest(inventory(app)) != manifest['base_tree']:
            raise ValueError('The installed app changed while preparing the update')
        stop_installed(app)
        previous = temporary / 'previous.app'
        app.rename(previous)
        try:
            stage.rename(app)
            verify(app)
        except BaseException:
            if app.exists():
                app.rename(temporary / 'failed.app')
            previous.rename(app)
            raise
        run('/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister', '-f', app)
        print(json.dumps({'installed': manifest['target_version'], 'backup': str(backup), 'path': str(app)}, ensure_ascii=False))
        # No launch from staging paths. Reopen the installed app normally after this command.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('create')
    create.add_argument('--base', type=Path, default=INSTALLED_APP)
    create.add_argument('--target', type=Path, required=True)
    create.add_argument('--output', type=Path, required=True)
    create.add_argument('--migrate-signer', help='Only for the first migration from ad-hoc to a pinned certificate')
    apply = commands.add_parser('apply')
    apply.add_argument('package', type=Path)
    apply.add_argument('--app', type=Path, default=INSTALLED_APP)
    apply.add_argument('--backups', type=Path, default=Path('~/Library/Application Support/Topit/Backups'))
    apply.add_argument('--migrate-signer')
    apply.add_argument('--check', action='store_true', help='Verify the installed base and staged target without installing or stopping Topit')
    args = parser.parse_args()
    if args.command == 'create':
        manifest = create_package(args.base, args.target, args.output, args.migrate_signer)
        print(json.dumps({'package': str(args.output), 'changed_files': len(manifest['changed']), 'target': manifest['target_version']}))
    else:
        apply_package(args)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print('Update failed: ' + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        sys.exit(1)
