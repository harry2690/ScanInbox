import importlib.util
import json
from pathlib import Path
import tempfile
import sys
from types import SimpleNamespace
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_tool", ROOT / "Scripts/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

sys.path.insert(0, str(ROOT / "Scripts"))
import release

class ReleaseTests(unittest.TestCase):
    def test_local_build_has_no_developer_identity_requirements(self):
        args = build.sign_arguments("-", Path("Example App.app"))
        self.assertEqual(args, ["codesign", "--force", "--sign", "-", "Example App.app"])

    def test_distribution_signing_enables_runtime_and_timestamp(self):
        args = build.sign_arguments("a" * 40, Path("Example App.app"))
        self.assertIn("--timestamp", args)
        self.assertIn("runtime", args)
        self.assertEqual(args[-1], "Example App.app")

    def test_release_rejects_empty_or_adhoc_identity(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "release.local.json"
            for identity in ("", "-", "invalid"):
                path.write_text(json.dumps(dict(signingIdentity=identity)))
                with self.assertRaises(ValueError):
                    build.load_release_config(path)
            path.write_text(json.dumps(dict(signingIdentity="a"*40)))
            self.assertEqual(build.load_release_config(path)["signingIdentity"], "a"*40)

    def test_new_install_and_public_example_have_no_printers(self):
        data = json.loads((ROOT / "config/settings.example.json").read_text())
        self.assertEqual(data["printers"], [])
        source = (ROOT / "Sources/ScanInbox/Model.swift").read_text()
        self.assertIn("var printers: [Printer] = []", source)
        self.assertNotIn("192.168.", source)

class PackagingTests(unittest.TestCase):
    def run_release(self, notarize=False, status="Accepted"):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            config = root / "release.local.json"
            config.write_text(json.dumps(dict(signingIdentity="a"*40, notaryProfile="Test-Profile")))
            args = ["release.py", "--config", str(config)] + (["--notarize"] if notarize else [])
            with patch.object(release, "ROOT", root), patch.object(sys, "argv", args), patch.object(release.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(dict(status=status)))) as run:
                if status != "Accepted" and notarize:
                    with self.assertRaises(SystemExit):
                        release.main()
                else:
                    release.main()
                return [call.args[0] for call in run.call_args_list]

    def test_packaging_does_not_submit_without_explicit_flag(self):
        commands = self.run_release()
        self.assertEqual(sum(cmd[0] == "ditto" for cmd in commands), 1)
        self.assertFalse(any("notarytool" in cmd for cmd in commands))

    def test_notarize_uses_keychain_and_repackages_after_staple(self):
        commands = self.run_release(notarize=True)
        submit = next(cmd for cmd in commands if "notarytool" in cmd)
        self.assertIn("--keychain-profile", submit)
        self.assertNotIn("--password", submit)
        staple = next(i for i, cmd in enumerate(commands) if "stapler" in cmd and "staple" in cmd)
        archives = [i for i, cmd in enumerate(commands) if cmd[0] == "ditto"]
        self.assertEqual(len(archives), 2)
        self.assertLess(staple, archives[-1])

    def test_rejected_notarization_is_not_stapled(self):
        commands = self.run_release(notarize=True, status="Invalid")
        self.assertFalse(any("stapler" in cmd for cmd in commands))

if __name__ == "__main__":
    unittest.main()
