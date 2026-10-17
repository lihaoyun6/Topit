import copy
import importlib.util
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
import release_assets as release


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.config = {'repository': 'owner/repo', 'version': '0.1.22', 'build': 32, 'signer_sha1': 'A' * 40}
        self.commit = 'b' * 40
        self.manifest = {'format': 'topit.release.v1', **self.config, 'source_commit': self.commit,
                         'assets': {name: 'c' * 64 for name in release.asset_names('0.1.22')}}

    def validate(self, value):
        release.validate_metadata(value, self.config, 'v0.1.22', self.commit)

    def test_valid_metadata(self):
        self.validate(self.manifest)

    def test_wrong_source_or_identity_is_rejected(self):
        for key in ['format', 'repository', 'version', 'build', 'source_commit', 'signer_sha1']:
            with self.subTest(key=key), self.assertRaises(ValueError):
                value = copy.deepcopy(self.manifest)
                value[key] = 'wrong'
                self.validate(value)

    def test_unexpected_or_missing_asset_is_rejected(self):
        for assets in [{}, {'../app.zip': 'c' * 64}, {**self.manifest['assets'], 'key.p12': 'c' * 64}]:
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                self.validate({**self.manifest, 'assets': assets})

    def test_invalid_hash_is_rejected(self):
        for digest in ['x' * 64, 'c' * 63, 1]:
            with self.subTest(digest=digest), self.assertRaises(ValueError):
                self.validate({**self.manifest, 'assets': {name: digest for name in self.manifest['assets']}})

    def test_tag_must_match_source_version(self):
        with self.assertRaises(ValueError):
            release.validate_metadata(self.manifest, self.config, 'v9.9.9', self.commit)

    def test_archive_cannot_escape_or_contain_symlinks(self):
        for name, symlink in [('../outside', False), ('/tmp/outside', False), ('Other.app/file', False),
                              ('Topit.app/../outside', False), ('Topit.app/Contents/link', True)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / 'app.zip'
                with zipfile.ZipFile(archive, 'w') as bundle:
                    info = zipfile.ZipInfo(name)
                    if symlink:
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    bundle.writestr(info, b'test')
                with self.assertRaises(ValueError):
                    release.extract_app(archive, root / 'extract')

    def test_archive_restores_executable_permission(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with zipfile.ZipFile(root / 'app.zip', 'w') as bundle:
                info = zipfile.ZipInfo('Topit.app/Contents/MacOS/Topit')
                info.external_attr = (stat.S_IFREG | 0o755) << 16
                bundle.writestr(info, b'test')
            app = release.extract_app(root / 'app.zip', root / 'extract')
            self.assertEqual((app / 'Contents/MacOS/Topit').stat().st_mode & 0o777, 0o755)


if __name__ == '__main__':
    unittest.main()
