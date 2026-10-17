import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'Scripts/topit_update.py'
spec = importlib.util.spec_from_file_location('topit_update', path)
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class UpdateProtocolTests(unittest.TestCase):
    def test_rejects_escaping_paths(self):
        for path in ['/Applications/Topit.app', '../Contents/file', 'Contents/../../file',
                     'Contents//file', 'Contents/./file', 'payload/file', 'Contents\\file', '']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                update.safe_path(path)

    def test_allows_internal_file(self):
        self.assertEqual(str(update.safe_path('Contents/MacOS/Topit')), 'Contents/MacOS/Topit')

    def test_requirement_is_pinned_to_certificate_and_app(self):
        requirement = update.stable_requirement('ab' * 20)
        self.assertIn('identifier "com.lihaoyun6.Topit"', requirement)
        self.assertIn('certificate leaf = H"' + 'AB' * 20 + '"', requirement)
        self.assertNotIn('cdhash', requirement)

    def test_rejects_identity_names_and_wildcards(self):
        for value in ['-', 'CodexSuper Local', 'a' * 39, 'x' * 40, 'a' * 41]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                update.stable_requirement(value)

    def test_tree_digest_does_not_depend_on_listing_order(self):
        a = {'Contents/b': {'sha256': 'b' * 64, 'mode': 420}, 'Contents/a': {'sha256': 'a' * 64, 'mode': 493}}
        self.assertEqual(update.tree_digest(a), update.tree_digest(dict(reversed(list(a.items())))))

    def test_tree_digest_detects_mode_and_content_changes(self):
        base = {'Contents/a': {'sha256': 'a' * 64, 'mode': 420}}
        self.assertNotEqual(update.tree_digest(base), update.tree_digest({'Contents/a': {'sha256': 'a' * 64, 'mode': 493}}))
        self.assertNotEqual(update.tree_digest(base), update.tree_digest({'Contents/a': {'sha256': 'b' * 64, 'mode': 420}}))

    def test_manifest_rejects_unexpected_app(self):
        with self.assertRaises(ValueError):
            update.validate_manifest({'format': update.FORMAT, 'bundle_id': 'another.app'})

    def test_manifest_rejects_duplicate_and_conflicting_paths(self):
        manifest = {'format': update.FORMAT, 'bundle_id': update.BUNDLE_ID,
                    'files': {'Contents/a': {'sha256': 'a' * 64, 'mode': 420}},
                    'changed': ['Contents/a', 'Contents/a'], 'removed': []}
        with self.assertRaises(ValueError):
            update.validate_manifest(manifest)
        manifest['changed'] = ['Contents/a']
        manifest['removed'] = ['Contents/a']
        with self.assertRaises(ValueError):
            update.validate_manifest(manifest)

    def test_manifest_rejects_group_or_world_writable_payload(self):
        manifest = {'format': update.FORMAT, 'bundle_id': update.BUNDLE_ID,
                    'files': {'Contents/a': {'sha256': 'a' * 64, 'mode': 0o777}},
                    'changed': ['Contents/a'], 'removed': []}
        with self.assertRaises(ValueError):
            update.validate_manifest(manifest)


if __name__ == '__main__':
    unittest.main()
