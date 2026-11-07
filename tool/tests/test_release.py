"""Offline wrapper regressions; never invoke real release automation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "project"
        (self.root / "tool").mkdir(parents=True)
        (self.root / "keys").mkdir()
        self.wrapper = self.root / "tool/release.py"
        shutil.copyfile(ROOT / "tool/release.py", self.wrapper)
        self.backend = Path(self.temp.name) / "automation"
        (self.backend / "scripts").mkdir(parents=True)
        (self.backend / "scripts/release_desktop.py").write_text(
            "import json, sys\n"
            "print(json.dumps({'sentinel': 'fake-backend', 'args': sys.argv[1:]}))\n"
        )
        self.config = self.root / "keys/desktop-release.json"
        self.config.write_text('{}')

    def invoke(self, *args, backend=True):
        env = os.environ.copy()
        env.pop("MACOS_RELEASE_SKILL", None)
        if backend:
            env["MACOS_RELEASE_SKILL"] = str(self.backend)
        return subprocess.run(
            [sys.executable, "-I", str(self.wrapper), *args],
            cwd=self.root, env=env, text=True, capture_output=True,
        )

    def forwarded(self, *args):
        result = self.invoke(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["sentinel"], "fake-backend")
        return payload["args"]

    def test_missing_config_fails_before_external_tools(self):
        self.config.unlink()
        result = self.invoke("prepare", backend=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release configuration missing", result.stderr)
        self.assertNotIn("MACOS_RELEASE_SKILL", result.stderr)
        self.assertNotIn("fake-backend", result.stdout)

    def test_default_config_for_plan_and_prepare(self):
        for command in ("plan", "prepare"):
            with self.subTest(command=command):
                self.assertEqual(self.forwarded(command), [
                    command, "--config", str(self.config),
                ])

    def test_explicit_config_space_and_equals_without_duplicate_default(self):
        self.config.unlink()
        custom = self.root / "custom config.json"
        custom.write_text('{}')
        for command in ("plan", "prepare"):
            for options in (["--config", str(custom)], [f"--config={custom}"]):
                with self.subTest(command=command, options=options):
                    self.assertEqual(self.forwarded(command, *options), [command, *options])

    def test_explicit_missing_file_fails(self):
        result = self.invoke("plan", "--config", str(self.root / "absent.json"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release configuration missing", result.stderr)
        self.assertNotIn("fake-backend", result.stdout)

    def test_prepare_has_no_hardcoded_matomo_or_define_file_requirement(self):
        # No defines file exists: only the backend may read config-defined inputs.
        self.assertFalse((self.root / "keys/release-defines.json").exists())
        self.assertEqual(self.forwarded("prepare")[0], "prepare")
        (self.root / "keys/release-defines.json").write_text(json.dumps({
            "SKILLDECK_MATOMO_URL": "https://analytics.example.com/matomo.php",
            "SKILLDECK_MATOMO_SITE_ID": "42",
        }))
        self.assertEqual(self.forwarded("prepare")[0], "prepare")

    def test_saved_run_commands_do_not_require_local_config(self):
        self.config.unlink()
        run = self.root / "dist/saved-run"
        run.mkdir(parents=True)
        # Prepared runs are not tagged, so no real Git operation is possible.
        (run / "desktop-release-state.json").write_text('{"status":"prepared"}')
        for command in ("resume", "publish", "status"):
            with self.subTest(command=command):
                args = [command, "--run-dir", str(run)]
                self.assertEqual(self.forwarded(*args), args)

    def test_missing_config_argument_fails_clearly(self):
        for options in (["--config"], ["--config="], ["--config", "--target", "macos-arm64"]):
            with self.subTest(options=options):
                result = self.invoke("prepare", *options, backend=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--config requires a file path", result.stderr)

    def test_help_is_forwarded_without_local_config(self):
        self.config.unlink()
        for args in (["-h"], ["--help"], ["prepare", "--help"], ["plan", "-h"]):
            with self.subTest(args=args):
                self.assertEqual(self.forwarded(*args), args)

    def test_backend_failure_is_forwarded_without_tagging(self):
        (self.backend / "scripts/release_desktop.py").write_text("raise SystemExit(7)\n")
        self.assertEqual(self.invoke("prepare", "--publish").returncode, 7)

    def test_example_schema_and_destinations(self):
        config = json.loads((ROOT / "release/desktop.example.json").read_text())
        self.assertEqual(config["schema_version"], 1)
        self.assertEqual(config["project_root"], "..")
        self.assertEqual(config["public_base_url"], "https://download.example.com")
        self.assertEqual(config["bucket"], "example-release-bucket")
        self.assertEqual(config["object_prefix"], "example/stable")
        self.assertEqual(config["sparkle_account"], "example-sparkle-account")
        windows = config["targets"]["windows-x64"]
        self.assertEqual(windows["ssh_host"], "windows-build-host")
        self.assertEqual(windows["remote_project_root"], "D:/path/to/project")
        for target in config["targets"].values():
            for field in ("appcast_key", "latest_key"):
                self.assertTrue(target[field].startswith("example/stable/"))
            for field in ("compatibility_appcasts", "initialize_indexes"):
                self.assertTrue(all(key.startswith("example/stable/") for key in target.get(field, [])))


if __name__ == "__main__":
    unittest.main()
