import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
SPEC=importlib.util.spec_from_file_location('badges',Path(__file__).with_name('update_readme_badges.py'))
badges=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(badges)
class BadgeEvidenceTests(unittest.TestCase):
    def test_source_content_and_version_change_digest_but_docs_do_not(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for name in ['Package.swift','Resources/Info.plist','scripts/build.sh','scripts/Icon.swift','Sources/App/main.swift','Tests/Core/test.swift']:
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(name)
            with patch.object(badges,'ROOT',root):
                before=badges.digest();(root/'README.md').write_text('Edited prose')
                self.assertEqual(before,badges.digest())
                (root/'Sources/App/main.swift').write_text('Changed behavior')
                changed=badges.digest();self.assertNotEqual(before,changed)
                (root/'Resources/Info.plist').write_text('New version')
                self.assertNotEqual(changed,badges.digest())
    def test_badges_escape_labels_and_claim_local_validation(self):
        self.assertIn('&amp;',badges.badge('a&b','1','555555'))
        e={'version':'3.8','tests':127,'macos':'14.0'}
        text=badges.block(e)
        self.assertIn('local tests: 127 passing',text)
        self.assertIn('local build: verified',text)
        self.assertNotIn('CI passing',text)
if __name__=='__main__':unittest.main()
