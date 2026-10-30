# SPDX-License-Identifier: GPL-3.0-only

"""Exercise installation in a temporary XDG directory, never the user's DMS config."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts/install.sh"


@unittest.skipIf(os.geteuid() == 0, "the installer intentionally refuses root")
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="presentation hub test ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "config with spaces"
        self.plugins = self.config / "dms/plugins"
        self.destination = self.plugins / "presentation-hub"
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.config), "TMPDIR": str(self.root)}

    def install(self):
        return subprocess.run(
            [str(INSTALLER)], env=self.env, capture_output=True, text=True, timeout=120
        )

    def test_installs_built_copy_and_never_overwrites(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.destination / "plugin.json").read_text())
        self.assertEqual(manifest["id"], "presentationHub")
        core = self.destination / "bin/presentation-hub-core"
        self.assertTrue(os.access(core, os.X_OK))
        self.assertEqual(subprocess.run([str(core), "--help"], capture_output=True).returncode, 0)
        self.assertFalse(self.destination.is_symlink())
        self.assertFalse(list(self.plugins.glob(".presentation-hub-install.*")))

        marker = self.destination / "user-data"
        marker.write_text("preserve me")
        second = self.install()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("never overwrites", second.stderr)
        self.assertEqual(marker.read_text(), "preserve me")

    def test_refuses_duplicate_id_in_another_directory(self):
        other = self.plugins / "existing-plugin"
        other.mkdir(parents=True)
        (other / "plugin.json").write_text('{"id": "presentationHub"}')
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already registered", result.stderr)
        self.assertFalse(self.destination.exists())

    def test_failed_build_does_not_publish_a_partial_plugin(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        cmake = fake_bin / "cmake"
        cmake.write_text("#!/bin/sh\necho build failed >&2\nexit 1\n")
        cmake.chmod(0o755)
        self.env["PATH"] = str(fake_bin) + os.pathsep + self.env["PATH"]
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("build failed", result.stderr)
        self.assertFalse(self.destination.exists())
        self.assertFalse(list(self.root.glob("presentation-hub-install.*")))

    def test_refuses_existing_symlink(self):
        self.plugins.mkdir(parents=True)
        self.destination.symlink_to(self.root / "missing-target")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.destination.is_symlink())


if __name__ == "__main__":
    unittest.main()
