import subprocess
import tempfile
import unittest
from pathlib import Path
from check_repository import files, findings, prohibited_name

class RepositoryChecksTests(unittest.TestCase):
    def test_guard_includes_new_source_and_excludes_ignored_local_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / '.gitignore').write_text('private/\n')
            (root / 'tracked.swift').write_text('let example = true\n')
            subprocess.run(['git', '-C', str(root), 'add', '.gitignore', 'tracked.swift'], check=True)
            (root / 'new source.swift').write_text('let example = false\n')
            (root / 'private').mkdir()
            (root / 'private' / 'audit.json').write_text('{}')
            self.assertEqual(set(map(str, files(root))), {'.gitignore', 'tracked.swift', 'new source.swift'})
    def test_secret_findings_never_need_raw_value_output(self):
        token = ("ghp" + "_" + "a" * 36).encode()
        self.assertEqual(findings(b"one\n" + token), [("github-token", 2)])
        key = ("-----BEGIN " + "PRIVATE KEY-----").encode()
        self.assertEqual(findings(key), [("private-key", 1)])
    def test_exact_historical_guard_literal_is_not_a_private_key(self):
        marker = b"-----BEGIN " + b"PRIVATE KEY-----"
        guard = b'assert b"' + marker + b'" not in data\n'
        self.assertEqual(findings(guard), [])
        single_quote_guard = b"assert b'" + marker + b"' not in data\n"
        self.assertEqual(findings(single_quote_guard), [])
        real = marker + b"\nQUJD\n-----END PRIVATE KEY-----\n"
        self.assertEqual(findings(guard + real), [("private-key", 2)])
        self.assertEqual(findings(b"value = " + marker), [("private-key", 1)])
    def test_guard_literal_does_not_suppress_other_credentials(self):
        guard = b'assert b"' + b"-----BEGIN " + b'PRIVATE KEY-----" not in data\n'
        token = ("ghp" + "_" + "a" * 36).encode()
        self.assertEqual(findings(guard + token), [("github-token", 2)])
    def test_home_path_and_secrets_only_history_mode(self):
        value = ("/" + "Users" + "/sampleperson/project").encode()
        self.assertEqual(findings(value), [("machine-home-path", 1)])
        self.assertEqual(findings(value, secrets_only=True), [])
    def test_normal_source_and_public_media_names(self):
        self.assertEqual(findings(b"let token = userInput; saveToKeychain(token)"), [])
        for name in ["local/analytics.sqlite", "accessToken.json", "secret.p12", "dist/App.app/Info.plist", ".env.local"]:
            self.assertTrue(prohibited_name(name))
        for name in ["docs/media/demo.png", "docs/presentation/MakerGlance.pptx", "LICENSE"]:
            self.assertFalse(prohibited_name(name))

if __name__ == "__main__": unittest.main()
