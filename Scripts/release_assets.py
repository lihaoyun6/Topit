#!/usr/bin/env python3
"""Verify locally signed release assets on GitHub without possessing a signing key."""
import argparse
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile

from topit_update import BUNDLE_ID, inventory, sha256, stable_requirement, tree_digest, validate_manifest, verify

ROOT = Path(__file__).resolve().parents[1]


def asset_names(version):
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Release version must be X.Y.Z')
    return [f'Topit-{version}-macOS-universal.zip', f'Topit-{version}.topitupdate']


def validate_metadata(manifest, config, tag, commit):
    if manifest.get('format') != 'topit.release.v1':
        raise ValueError('Unknown release format')
    version = config['version']
    if tag != 'v' + version or manifest.get('version') != version or manifest.get('build') != config['build']:
        raise ValueError('Release version/build does not match the checked-out source')
    if not re.fullmatch(r'[0-9a-f]{40}', commit) or manifest.get('source_commit') != commit:
        raise ValueError('Release source commit mismatch')
    if manifest.get('repository') != config['repository'] or manifest.get('signer_sha1') != config['signer_sha1']:
        raise ValueError('Release repository/signing identity mismatch')
    assets = manifest.get('assets', {})
    if set(assets) != set(asset_names(version)):
        raise ValueError('Missing or unexpected release asset')
    if any(not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest) for digest in assets.values()):
        raise ValueError('Invalid release asset digest')


def extract_app(archive, destination):
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate app archive entries')
        for item in bundle.infolist():
            name = PurePosixPath(item.filename)
            if '\\' in item.filename or name.is_absolute() or '..' in name.parts or not name.parts or name.parts[0] != 'Topit.app':
                raise ValueError('Unsafe app archive entry')
            if stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError('App archive symlinks are unsupported')
        bundle.extractall(destination)
        # zipfile does not restore executable permissions.
        for item in bundle.infolist():
            path = destination / item.filename
            if path.is_file():
                path.chmod((item.external_attr >> 16) & 0o777 or 0o644)
    return destination / 'Topit.app'


def verify_assets(directory, tag, commit, config):
    manifest = json.loads((directory / 'release-manifest.json').read_text())
    validate_metadata(manifest, config, tag, commit)
    expected = set(manifest['assets']) | {'release-manifest.json', 'SHA256SUMS.txt'}
    if {p.name for p in directory.iterdir()} != expected:
        raise ValueError('Release directory has missing or unexpected files')
    for name, digest in manifest['assets'].items():
        if sha256(directory / name) != digest:
            raise ValueError('Release hash mismatch: ' + name)
    expected_sums = ''.join(f'{digest}  {name}\n' for name, digest in sorted(manifest['assets'].items()))
    if (directory / 'SHA256SUMS.txt').read_text() != expected_sums:
        raise ValueError('Checksum list mismatch')
    app_zip, update_zip = [directory / name for name in asset_names(config['version'])]
    with tempfile.TemporaryDirectory(prefix='topit-release-verify-') as temporary:
        app = extract_app(app_zip, Path(temporary))
        with (app / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), str(info.get('CFBundleVersion')), info.get('TopitSourceRevision')) != (BUNDLE_ID, config['version'], str(config['build']), commit):
            raise ValueError('Signed app metadata/source commit mismatch')
        verify(app, stable_requirement(config['signer_sha1']))
        architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(app / 'Contents/MacOS/Topit')], text=True).split()
        if set(architectures) != {'arm64', 'x86_64'}:
            raise ValueError('Release app must contain arm64 and x86_64')
        files = inventory(app)
        with zipfile.ZipFile(update_zip) as archive:
            update = json.loads(archive.read('manifest.json'))
            validate_manifest(update)
            if update['signer_migration'] is not None or update['target_version'] != config['version'] or str(update['target_build']) != str(config['build']):
                raise ValueError('Update target/signing migration mismatch')
            if update['files'] != files or update['target_tree'] != tree_digest(files):
                raise ValueError('Full app and incremental update disagree')
            expected_entries = {'manifest.json'} | {'payload/' + name for name in update['changed']}
            if len(archive.namelist()) != len(expected_entries) or set(archive.namelist()) != expected_entries:
                raise ValueError('Unexpected update payload entries')
            import hashlib
            for name in update['changed']:
                if hashlib.sha256(archive.read('payload/' + name)).hexdigest() != files[name]['sha256']:
                    raise ValueError('Update payload hash mismatch')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', required=True, type=Path)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    config = json.loads((ROOT / 'Config/release.json').read_text())
    manifest = verify_assets(args.assets, args.tag, args.commit, config)
    print(json.dumps({'verified': True, 'version': manifest['version'], 'source_commit': manifest['source_commit']}))


if __name__ == '__main__':
    main()
