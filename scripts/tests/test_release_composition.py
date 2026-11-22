"""scripts/check-bundle.sh --release-composition; run with python3 -m unittest discover -s scripts/tests -v.

The Release scan runs for real against controlled bundles in a temporary directory: a copy of a
system Mach-O executable, with Debug-only development names appended where a case needs them.
Nothing is built or written into this repository.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "scripts/check-bundle.sh"
# Every name that DevelopmentComposition, DevelopmentPythonTool and DevelopmentApprovalProbe
# compile only in Debug.
DEBUG_ONLY = ("python_run", "DevelopmentPythonTool", "MemoshiDevelopmentPythonTool", "development_note",
              "MemoshiDevelopmentApprovalTool", "MemoshiDevelopmentBrowserReview", "DevelopmentApprovalProbe",
              "DevelopmentLaunchArgument", "development-approval-tool")


def scan(*bundles):
    env = {key: value for key, value in os.environ.items() if key != "MEMOSHI_BUILD_ROOT"}
    return subprocess.run([str(CHECK), "--release-composition", *map(str, bundles)], cwd=ROOT, env=env,
                          capture_output=True, text=True)


class ReleaseCompositionTests(unittest.TestCase):
    def bundle(self, directory, name, appended=b""):
        """An app-shaped directory with one Mach-O executable and one plain resource file."""
        bundle = Path(directory).resolve() / name
        (bundle / "Frameworks").mkdir(parents=True)
        executable = bundle / "Frameworks/Tool.dylib"
        shutil.copyfile("/usr/bin/true", executable)
        with executable.open("ab") as file:
            file.write(appended)
        # Text resources may name the tools (licence or evidence text); only code is scanned.
        (bundle / "notes.txt").write_text(" ".join(DEBUG_ONLY))
        return bundle

    def test_a_bundle_without_development_names_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            app, mobile = self.bundle(directory, "Memoshi.app"), self.bundle(directory, "MemoshiMobile.app")
            result = scan(app, mobile)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count("no Debug-only development name in 1 Mach-O file(s)"), 2)

    def test_each_debug_only_name_in_code_fails(self):
        for name in DEBUG_ONLY:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                clean = self.bundle(directory, "Memoshi.app")
                mobile = self.bundle(directory, "MemoshiMobile.app", b"\0" + name.encode() + b"\0")
                result = scan(clean, mobile)
                self.assertEqual(result.returncode, 1)
                self.assertIn(f"Frameworks/Tool.dylib contains the Debug-only '{name}'", result.stderr)
                self.assertIn(f"ok: no Debug-only development name in 1 Mach-O file(s) of {clean}", result.stdout)
                self.assertNotIn(str(mobile) + "\n", result.stdout)
                self.assertIn("error: 1 Release composition problem(s)", result.stderr)

    def test_a_path_without_code_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            empty = Path(directory).resolve() / "Empty.app"
            empty.mkdir()
            (empty / "notes.txt").write_text("text")
            for path, message in ((empty, "has no Mach-O file"), (empty.with_name("Missing.app"), "no bundle at")):
                with self.subTest(path=path.name):
                    result = scan(path)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(message, result.stderr)
            self.assertEqual(scan().returncode, 2)


if __name__ == "__main__":
    unittest.main()
