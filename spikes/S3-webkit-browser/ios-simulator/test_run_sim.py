"""Self-test for run-sim.py's create-only evidence names, with every subprocess replaced.

  python3 -B -m unittest discover -s spikes/S3-webkit-browser/ios-simulator -p 'test_*.py'

Nothing is resolved, built, installed or launched.
"""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
# What the environment held before any test loaded run-sim.py; loading it must not change it.
BUILD_ROOT_AT_IMPORT = os.environ.get("MEMOSHI_BUILD_ROOT")


class BuildAttemptTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        # run-sim.py reads its build root once, at load; no later test may see it.
        with mock.patch.dict(os.environ, {"MEMOSHI_BUILD_ROOT": self.scratch.name}):
            spec = importlib.util.spec_from_file_location("run_sim", HERE / "run-sim.py")
            self.sim = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.sim)
        root = Path(self.scratch.name)
        self.run = root / "run"
        self.run.mkdir()
        (root / "package/Sources" / self.sim.TARGET).mkdir(parents=True)
        self.state = {"run": str(self.run), "scratch": str(root), "package": str(root / "package")}
        # Every command "fails": resolve is the first one whose exit code build() checks.
        self.sim.subprocess = types.SimpleNamespace(
            run=lambda *args, **kwargs: types.SimpleNamespace(returncode=1, stdout=""),
            PIPE=None, STDOUT=None)

    def test_build_can_be_retried_after_a_failed_resolve(self):
        self.assertEqual(self.sim.build(self.state), 1)
        self.assertTrue((self.run / "sources.json").exists())
        self.assertTrue((self.run / "resolve.log").exists())
        self.assertFalse((self.run / "build.log").exists())
        self.assertEqual(self.sim.build(self.state), 1)
        self.assertTrue((self.run / "sources-2.json").exists())
        self.assertTrue((self.run / "resolve-2.log").exists())

    def test_loading_run_sim_leaves_the_environment_alone(self):
        self.assertEqual(os.environ.get("MEMOSHI_BUILD_ROOT"), BUILD_ROOT_AT_IMPORT)


if __name__ == "__main__":
    unittest.main()
