import argparse
import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'Viewin-0.1.0.zip'
        self.archive.write_bytes(b'test archive')
        self.url = 'https://github.com/FeliksLv01/Viewin/releases/download/v0.1.0/' + self.archive.name
        self.signature = base64.b64encode(bytes(64)).decode()
        self.appcast = self.root / 'appcast.xml'

    def write_appcast(self, **changes):
        values = dict(build='1', version='0.1.0', url=self.url,
                      length=str(self.archive.stat().st_size), signature=self.signature)
        values.update(changes)
        self.appcast.write_text('''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><item><sparkle:version>{build}</sparkle:version>
        <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
        <enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}"/>
        </item></channel></rss>'''.format(**values))

    def validate(self):
        release.validate_appcast(self.appcast, version='0.1.0', build='1', archive=self.archive, download_url=self.url)

    def test_appcast_metadata_matches_archive(self):
        self.write_appcast()
        self.validate()

    def test_mismatched_archive_metadata_is_rejected(self):
        for change in [dict(build='2'), dict(version='0.2.0'), dict(length='1'),
                       dict(url='https://example.com/other.zip'), dict(signature='')]:
            with self.subTest(change=change):
                self.write_appcast(**change)
                with self.assertRaises(ValueError):
                    self.validate()

    def test_debug_app_cannot_be_prepared(self):
        app = self.root / 'Viewin Debug.app'
        (app / 'Contents').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.felikslv.Viewin.debug'}))
        with patch.object(release, 'run') as command:
            with self.assertRaises(ValueError):
                release.prepare(argparse.Namespace(app=app))
            command.assert_not_called()

    def test_modified_prepared_files_are_not_uploaded(self):
        self.write_appcast()
        metadata = dict(repository='FeliksLv01/Viewin', tag='v0.1.0', version='0.1.0', build='1',
                        archive=self.archive.name, notes='notes.md',
                        archiveSHA256=release.digest(self.archive), appcastSHA256=release.digest(self.appcast))
        (self.root / 'release.json').write_text(json.dumps(metadata))
        self.archive.write_bytes(b'changed after preparation')
        with patch.object(release, 'run') as command:
            with self.assertRaises(ValueError):
                release.draft(argparse.Namespace(directory=self.root))
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
