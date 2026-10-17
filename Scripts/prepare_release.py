#!/usr/bin/env python3
"""Build/sign locally, stage a draft release, and dispatch GitHub's verified publisher."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from release_assets import ROOT, asset_names, verify_assets
from topit_update import sha256


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='Upload the signed assets as a draft and trigger release.yml')
    args = parser.parse_args()
    if output('git', 'status', '--porcelain'):
        raise ValueError('Commit all source changes before preparing a release')
    config = json.loads((ROOT / 'Config/release.json').read_text())
    local = json.loads((ROOT / 'Config/signing.local.json').read_text())
    if local['identity_sha1'].upper() != config['signer_sha1']:
        raise ValueError('Local signer differs from the pinned public release identity')
    revision = output('git', 'rev-parse', 'HEAD')
    version = config['version']
    tag = 'v' + version
    directory = ROOT / 'dist' / tag
    directory.mkdir(parents=True, exist_ok=False)
    app_name, update_name = asset_names(version)
    subprocess.run([sys.executable, str(ROOT / 'Scripts/build_update.py'), '--version', version,
                    '--build', str(config['build']), '--source-revision', revision,
                    '--archive', str(directory / app_name), '--output', str(directory / update_name)], cwd=ROOT, check=True)
    assets = {name: sha256(directory / name) for name in [app_name, update_name]}
    manifest = {'format': 'topit.release.v1', 'repository': config['repository'], 'version': version,
                'build': config['build'], 'source_commit': revision, 'signer_sha1': config['signer_sha1'], 'assets': assets}
    (directory / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (directory / 'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(assets.items())))
    verify_assets(directory, tag, revision, config)
    if output('git', 'status', '--porcelain') or output('git', 'rev-parse', 'HEAD') != revision:
        raise ValueError('Source changed during the release build; do not publish these assets')
    print(json.dumps({'prepared': str(directory), 'installed_app_changed': False}))
    if args.publish:
        notes = ROOT / 'docs' / 'releases' / (tag + '.md')
        if not notes.is_file():
            raise ValueError('Write release notes before publication: ' + str(notes))
        subprocess.run(['gh', 'release', 'create', tag, '--repo', config['repository'], '--target', revision,
                        '--draft', '--prerelease', '--title', 'Topit ' + version, '--notes-file', str(notes),
                        *[str(directory / name) for name in sorted(p.name for p in directory.iterdir())]], check=True)
        # A draft release may not yet have a Git tag. Publish the exact source ref
        # so Actions can check out and test it before publishing the release.
        subprocess.run(['git', 'push', 'origin', revision + ':refs/tags/' + tag], cwd=ROOT, check=True)
        subprocess.run(['gh', 'workflow', 'run', 'release.yml', '--repo', config['repository'], '--ref', 'main',
                        '-f', 'tag=' + tag], check=True)


if __name__ == '__main__':
    main()
