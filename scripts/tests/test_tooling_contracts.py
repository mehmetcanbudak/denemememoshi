"""Contracts of the CI scripts and workflows; run with python3 -m unittest discover -s scripts/tests -v.

Each shell script runs for real against a controlled scratch copy of the layout it reads
(`cd "$(dirname "$0")/.."`), with local temporary Git repositories where it needs Git. Nothing
is built, fetched remotely, signed or written into this repository.
"""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/lib"))
import license_policy

GIT = ["git", "-c", "user.name=Memoshi tests", "-c", "user.email=tests@memoshi.invalid",
       "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", "-c", "init.defaultBranch=main"]
# Runner- and release-only switches must not leak from the host into a controlled run.
DROPPED = ("MEMOSHI_BUILD_ROOT", "MEMOSHI_PI_SWIFT_SOURCE", "MEMOSHI_REQUIRE_RELEASE_DISK",
           "MEMOSHI_CI_MIN_FREE_GB", "GITHUB_ACTIONS")


def execute(arguments, cwd, **environment):
    env = {key: value for key, value in os.environ.items() if key not in DROPPED and not key.startswith("GIT_")}
    env.update({key: str(value) for key, value in environment.items()})
    return subprocess.run([str(item) for item in arguments], cwd=cwd, env=env, capture_output=True, text=True)


def git(repository, *arguments):
    result = execute(GIT + ["-C", repository] + list(arguments), repository)
    if result.returncode:
        raise AssertionError(f"git {arguments[0]} failed: {result.stderr}")
    return result.stdout.strip()


def copy_script(scratch, relative):
    target = Path(scratch) / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / relative, target)
    return target


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path


def workflow_events(text):
    """The events of a workflow's top-level `on:` key, in block, list or scalar form."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.fullmatch(r"""["']?on["']?:\s*(.*)""", line)
        if match is None:
            continue
        if match[1] and not match[1].startswith("#"):
            return re.findall(r"[a-z_]+", match[1])
        events = []
        for nested in lines[index + 1:]:
            if nested.strip() and not nested.startswith((" ", "#")):
                break
            key = re.fullmatch(r"  (?:- )?([a-z_]+):?\s*(?:#.*)?", nested)
            if key is not None:
                events.append(key[1])
        return events
    return []


class WorkflowContractTests(unittest.TestCase):
    def test_no_self_hosted_job_is_reachable_from_a_pull_request(self):
        self.assertEqual(workflow_events("on:\n  push:\n  pull_request_target:\n    types: [opened]\njobs:\n"),
                         ["push", "pull_request_target"])
        self.assertEqual(workflow_events("on: [push, pull_request]\n"), ["push", "pull_request"])
        workflows = sorted((ROOT / ".github/workflows").iterdir())
        self.assertTrue(workflows)
        for workflow in workflows:
            text = workflow.read_text()
            events = workflow_events(text)
            with self.subTest(workflow=workflow.name):
                self.assertTrue(events, "workflow triggers could not be read")
                if "self-hosted" in text:
                    # D90: self-hosted jobs run for pushes, schedules and manual runs only.
                    self.assertFalse({"pull_request", "pull_request_target"} & set(events))

    def test_release_copies_the_sdk_and_its_slice_tags_before_the_gate_reads_them(self):
        text = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn("run: scripts/check-prerequisites.sh", text)
        self.assertLess(text.index("run: scripts/check-prerequisites.sh"), text.index("release.py check-release-gates"))
        before_gate = text[text.index("- name: Copy the pinned SDK candidate"):text.index("release.py check-release-gates")]
        # In a release run a slice tag that the source re-pointed is an error, not a warning.
        self.assertIn('MEMOSHI_REQUIRE_RELEASE_DISK: "true"', before_gate)
        self.assertNotIn("output creation precedes this gate", text)

    def test_release_confirms_the_uploaded_build_number_not_any_usable_build(self):
        text = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertNotIn("testflight-status", text)
        upload = text.index("release.py upload-testflight")
        confirmation = text[upload:].split("release.py confirm-testflight-upload", 1)
        self.assertEqual(len(confirmation), 2, "no confirmation follows the upload")
        command = confirmation[1].split("\n\n", 1)[0]
        self.assertIn('--build-number "$INPUT_BUILD_NUMBER"', command)
        self.assertRegex(command, r"--timeout-minutes [1-9][0-9]*\b")


class PrerequisiteTests(unittest.TestCase):
    """scripts/check-prerequisites.sh copies the pinned Pi_Swift commit and creates its checkout."""

    @staticmethod
    def layout(base, tag, revision, manifest_tag=None, snapshot=None):
        repository = base / "Memoshi"
        script = copy_script(repository, "scripts/check-prerequisites.sh")
        for helper in sorted((ROOT / "scripts/lib").glob("*.py")):
            copy_script(repository, helper.relative_to(ROOT))
        write(repository / "scripts/lib/pi-swift-pin.sh",
              f"PI_SWIFT_TAG={tag}\nPI_SWIFT_REVISION={revision}\nPI_SWIFT_CHECKOUT=../Pi_Swift-{tag}\n")
        write(repository / "Packages/MemoshiCore/Package.swift",
              f'.package(path: "../../../Pi_Swift-{manifest_tag or tag}"),\n')
        write(repository / "Packages/MemoshiCore/Sources/Runtime/RuntimeConfiguration.swift",
              f'  public static let revision = "{snapshot or revision}"\n')
        return repository, script

    @staticmethod
    def source_with_slice(base, tag):
        source = base / "source"
        if not source.exists():
            source.mkdir()
            git(source, "init", "--quiet")
        git(source, "commit", "--quiet", "--allow-empty", "-m", tag)
        git(source, "tag", "--annotate", "--message", tag, tag)
        return source, git(source, "rev-parse", "HEAD")

    def test_a_moved_pin_reaches_the_sibling_and_gets_its_own_clean_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            source, first = self.source_with_slice(base, "slice-1")
            repository, script = self.layout(base, "slice-1", first)
            sibling = base / "Pi_Swift"

            def prerequisites(**environment):
                return execute([script], repository, MEMOSHI_PI_SWIFT_SOURCE=source, **environment)

            result = prerequisites()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(git(base / "Pi_Swift-slice-1", "rev-parse", "HEAD"), first)
            # The next slice is tagged after CI first copied the sibling; moving the pin copies
            # its commit and tag, then creates that slice's own checkout.
            _, second = self.source_with_slice(base, "slice-2")
            repository, script = self.layout(base, "slice-2", second)
            moved = prerequisites()
            self.assertEqual(moved.returncode, 0, moved.stderr)
            self.assertEqual(git(sibling, "rev-parse", "--verify", "refs/tags/slice-2^{commit}"), second)
            self.assertEqual(git(base / "Pi_Swift-slice-2", "rev-parse", "HEAD"), second)
            self.assertEqual(git(base / "Pi_Swift-slice-2", "status", "--porcelain", "--untracked-files=all"), "")
            # A slice tag that the source re-pointed is never silently replaced: an ordinary run
            # warns with the recovery command and a release run refuses.
            git(source, "commit", "--quiet", "--allow-empty", "-m", "later")
            git(source, "tag", "--force", "--annotate", "--message", "moved", "slice-1")
            ordinary = prerequisites()
            self.assertEqual(ordinary.returncode, 0, ordinary.stderr)
            self.assertIn("warning: could not copy every slice-* tag", ordinary.stderr)
            self.assertIn("git -C ../Pi_Swift tag -d <tag>", ordinary.stderr)
            release = prerequisites(MEMOSHI_REQUIRE_RELEASE_DISK="true")
            self.assertEqual(release.returncode, 1)
            self.assertIn("error: could not copy every slice-* tag", release.stderr)
            self.assertEqual(git(sibling, "rev-parse", "--verify", "refs/tags/slice-1^{commit}"), first)

    def test_a_checkout_that_is_not_the_unmodified_tagged_commit_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            source, revision = self.source_with_slice(base, "slice-1")
            write(source / "tracked.txt", "original\n")
            git(source, "add", "tracked.txt")
            git(source, "commit", "--quiet", "-m", "tracked")
            git(source, "tag", "--force", "--annotate", "--message", "slice-1", "slice-1")
            revision = git(source, "rev-parse", "HEAD")
            shutil.copytree(source, base / "Pi_Swift")
            repository, script = self.layout(base, "slice-1", revision)
            checkout = base / "Pi_Swift-slice-1"
            created = execute([script], repository)
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertIn("ok: created ../Pi_Swift-slice-1", created.stdout)

            def refused(reason):
                result = execute([script], repository)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(reason, result.stderr)

            (checkout / "tracked.txt").write_text("edited\n")
            refused("has changes, untracked or ignored files")
            git(checkout, "checkout", "--quiet", "--", "tracked.txt")
            write(checkout / "untracked.txt", "new\n")
            refused("has changes, untracked or ignored files")
            (checkout / "untracked.txt").unlink()
            git(checkout, "checkout", "--quiet", "--detach", "HEAD~1")
            refused("is not checked out at " + revision)
            git(checkout, "checkout", "--quiet", "--detach", revision)
            git(checkout, "tag", "--force", "slice-1", revision)
            refused("has no annotated tag slice-1 that points at " + revision)
            git(checkout, "tag", "--force", "--annotate", "--message", "slice-1", "slice-1", revision)
            self.assertEqual(execute([script], repository).returncode, 0)
            # The manifest and the runtime's recorded revision must name the same pin.
            self.layout(base, "slice-1", revision, manifest_tag="slice-0")
            refused("does not use Pi_Swift from ../../../Pi_Swift-slice-1")
            self.layout(base, "slice-1", revision, snapshot="0" * 40)
            refused("PiDevelopmentSnapshot.revision")
            # Only active manifest code counts: a commented pinned line beside another live
            # Pi_Swift path is refused.
            manifest = repository / "Packages/MemoshiCore/Package.swift"
            self.layout(base, "slice-1", revision)
            manifest.write_text('// .package(path: "../../../Pi_Swift-slice-1"),\n'
                                '.package(path: "../../../Elsewhere/Pi_Swift-slice-1"),\n')
            refused("does not use Pi_Swift from ../../../Pi_Swift-slice-1 alone")
            manifest.write_text('.package(path: "../../../Pi_Swift-slice-1"),\n'
                                '.package(url: "../../../Pi_Swift", revision: "x"),\n')
            refused("does not use Pi_Swift from ../../../Pi_Swift-slice-1 alone")
            self.layout(base, "slice-1", revision)
            self.assertEqual(execute([script], repository).returncode, 0)

    def test_a_checkout_that_is_a_link_or_inside_another_clone_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            source, revision = self.source_with_slice(base, "slice-1")
            shutil.copytree(source, base / "Pi_Swift")
            repository, script = self.layout(base, "slice-1", revision)
            checkout = base / "Pi_Swift-slice-1"
            # A symbolic link to the working clone, which has the commit, tag and a clean tree.
            git(base / "Pi_Swift", "checkout", "--quiet", "--detach", revision)
            checkout.symlink_to(base / "Pi_Swift")
            linked = execute([script], repository)
            self.assertEqual(linked.returncode, 1, linked.stdout)
            self.assertIn("is a symbolic link", linked.stderr)
            # A plain directory inside another Git repository is not its own clone either.
            checkout.unlink()
            git(base, "init", "--quiet")
            checkout.mkdir()
            write(checkout / "Package.swift", "// not a clone\n")
            nested = execute([script], repository)
            self.assertEqual(nested.returncode, 1, nested.stdout)
            self.assertIn("is not its own Git clone", nested.stderr)
            shutil.rmtree(checkout)
            created = execute([script], repository)
            self.assertEqual(created.returncode, 0, created.stderr)
            self.assertFalse(checkout.is_symlink())

    def test_every_manifest_package_is_the_pinned_checkout_or_a_reviewed_dependency(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            source, revision = self.source_with_slice(base, "slice-1")
            shutil.copytree(source, base / "Pi_Swift")
            repository, script = self.layout(base, "slice-1", revision)
            manifest = repository / "Packages/MemoshiCore/Package.swift"
            pinned = '.package(path: "../../../Pi_Swift-slice-1"),\n'
            self.assertEqual(execute([script], repository).returncode, 0)
            # The committed manifest, pointed at this layout's checkout, passes as it stands.
            committed = (ROOT / "Packages/MemoshiCore/Package.swift").read_text()
            pin = dict(re.findall(r"^(PI_SWIFT_[A-Z]+)=(\S+)$", (ROOT / "scripts/lib/pi-swift-pin.sh").read_text(), re.M))
            manifest.write_text(committed.replace(pin["PI_SWIFT_CHECKOUT"].removeprefix("../"), "Pi_Swift-slice-1"))
            accepted = execute([script], repository)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            # A `//` inside a string literal is not a comment; a comment never counts.
            manifest.write_text(pinned + '.package(url: "https://github.com/apple/swift-nio", exact: "2.104.0"),\n'
                                '/* .package(url: "https://github.com/x/Pi_Swift.git", from: "1.0.0"), /* nested */ */\n'
                                '// .package(path: "../../../PiFork"),\n')
            commented = execute([script], repository)
            self.assertEqual(commented.returncode, 0, commented.stderr)
            for extra in ('.package(url: "https://github.com/x/Pi_Swift.git", from: "1.0.0"),\n',
                          '.package(path: "../../../PiFork"),\n',
                          '.package(url: "https://github.com/x/swift-nio", exact: "2.104.0"),\n',
                          '.package(\n  url: "https://example.invalid/tools" // reviewed?\n, from: "1.0.0"),\n',
                          '.package(name: "Pi", path: "../../../Pi_Swift-slice-1"),\n',
                          '.package(path: "../../../Pi_\\(slice)"),\n',
                          pinned):
                with self.subTest(extra=extra):
                    manifest.write_text(pinned + extra)
                    refused = execute([script], repository)
                    self.assertEqual(refused.returncode, 1, refused.stdout)
                    self.assertIn("does not use Pi_Swift from ../../../Pi_Swift-slice-1 alone", refused.stderr)
            manifest.write_text('/* .package(path: "../../../Pi_Swift-slice-1"), */\n')
            self.assertEqual(execute([script], repository).returncode, 1)

    def test_ignored_files_in_the_checkout_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            source, revision = self.source_with_slice(base, "slice-1")
            write(source / ".gitignore", "Sources/Generated/\n")
            git(source, "add", ".gitignore")
            git(source, "commit", "--quiet", "-m", "ignore")
            git(source, "tag", "--force", "--annotate", "--message", "slice-1", "slice-1")
            revision = git(source, "rev-parse", "HEAD")
            shutil.copytree(source, base / "Pi_Swift")
            repository, script = self.layout(base, "slice-1", revision)
            self.assertEqual(execute([script], repository).returncode, 0)
            # SwiftPM compiles every source in a target directory, ignored or not.
            write(base / "Pi_Swift-slice-1/Sources/Generated/Extra.swift", "let extra = 1\n")
            ignored = execute([script], repository)
            self.assertEqual(ignored.returncode, 1, ignored.stdout)
            self.assertIn("has changes, untracked or ignored files", ignored.stderr)


class GeneratedMLSTests(unittest.TestCase):
    def test_regenerated_mls_outputs_must_match_the_checked_in_files(self):
        bindings = "Packages/MemoshiMLS/Sources/MemoshiMLSNativeBindings/MemoshiMLSNativeBindings.swift"
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory).resolve()
            git(repository, "init", "--quiet")
            script = copy_script(repository, "scripts/check-mls-generated.sh")
            write(repository / bindings, "// generated\n")
            write(repository / "Packages/MemoshiMLS/Generated/include/module.modulemap", "module M {}\n")
            write(repository / "Packages/MemoshiMLS/Native/Licenses/manifest.json", "{}\n")
            write(repository / "Packages/MemoshiMLS/Native/src/lib.rs", "// source\n")
            git(repository, "add", "--all")
            git(repository, "commit", "--quiet", "-m", "checked in")
            clean = execute([script], repository)
            self.assertEqual(clean.returncode, 0, clean.stderr)
            # A source edit alone is not drift; the regenerated outputs are what must match.
            (repository / "Packages/MemoshiMLS/Native/src/lib.rs").write_text("// edited source\n")
            self.assertEqual(execute([script], repository).returncode, 0)
            with (repository / bindings).open("a") as stream:
                stream.write("// regenerated differently\n")
            stale = execute([script], repository)
            self.assertEqual(stale.returncode, 1)
            self.assertIn(bindings, stale.stderr)
            git(repository, "checkout", "--quiet", "--", bindings)
            added = write(repository / "Packages/MemoshiMLS/Native/Licenses/new-crate-1.0.0/LICENSE", "terms\n")
            unretained = execute([script], repository)
            self.assertEqual(unretained.returncode, 1)
            self.assertIn("new-crate-1.0.0/LICENSE", unretained.stderr)
            added.unlink()
            (repository / "Packages/MemoshiMLS/Generated/include/module.modulemap").unlink()
            self.assertEqual(execute([script], repository).returncode, 1)

    def test_ci_checks_the_regenerated_outputs_right_after_building_them(self):
        steps = re.findall(r'^step "[^"]+" (.+)$', (ROOT / "scripts/ci.sh").read_text(), re.MULTILINE)
        build = steps.index("scripts/build-memoshi-mls.sh")
        self.assertEqual(steps[build + 1], "scripts/check-mls-generated.sh")


class MLSBuildInstallTests(unittest.TestCase):
    """build-memoshi-mls.sh's staging and installation, with stand-ins for the compilers.

    Nothing is compiled: `rustup`, `xcrun`, `xcodebuild` and the two Python inventory steps are
    replaced by scripts that write controlled files where the real tools write theirs.
    """

    outputs = {
        "bindings": "Sources/MemoshiMLSNativeBindings/MemoshiMLSNativeBindings.swift",
        "header": "Generated/include/MemoshiMLSNativeFFI.h",
        "module map": "Generated/include/module.modulemap",
        "binary": "Artifacts/MemoshiMLSNativeFFI.xcframework/library",
        "manifest": "Artifacts/payload-manifest.json",
    }
    stand_ins = {
        "rustup": """#!/bin/bash
shift 2
tool=$1
shift
case "$tool $*" in
  "rustc --version") echo "rustc 1.97.0 (controlled stand-in)" ;;
  rustc*target-libdir) echo "$STAND_IN/libdir" ;;
  "cargo build"*)
    while [ "$#" -gt 1 ]; do shift; done
    mkdir -p "$CARGO_TARGET_DIR/$1/release"
    echo new >"$CARGO_TARGET_DIR/$1/release/libmemoshi_mls_native.a" ;;
  "cargo run"*)
    while [ "$1" != --out-dir ]; do shift; done
    for file in MemoshiMLSNativeBindings.swift MemoshiMLSNativeFFI.h MemoshiMLSNativeFFI.modulemap; do
      echo new >"$2/$file"
    done ;;
  *) exit 64 ;;
esac
""",
        "xcrun": "#!/bin/bash\necho /controlled/sdk\n",
        "xcodebuild": """#!/bin/bash
[ -z "${STAND_IN_FAIL:-}" ] || [ "$STAND_IN_FAIL" != xcodebuild ] || exit 70
while [ "$#" -gt 0 ]; do
  case "$1" in
    -headers) headers=$2 ;;
    -output) output=$2 ;;
  esac
  shift
done
echo "$output" >"$STAND_IN/xcodebuild-output"
mkdir -p "$output"
echo plist >"$output/Info.plist"
cp -R "$headers" "$output/Headers"
[ "${STAND_IN_FAIL:-}" != headers ] || echo stale >>"$output/Headers/MemoshiMLSNativeFFI.h"
echo new >"$output/library"
""",
        "python3": """#!/bin/bash
case "$1" in
  */retain-memoshi-mls-licenses.py) [ "${STAND_IN_FAIL:-}" != licences ] || exit 1 ;;
  */memoshi-mls-payload-manifest.py) echo new >"$(dirname "$1")/../Packages/MemoshiMLS/Artifacts/payload-manifest.json" ;;
esac
""",
    }

    def build(self, directory, fail=""):
        base = Path(directory).resolve()
        scratch, tools = base / "Memoshi", base / "tools"
        package = scratch / "Packages/MemoshiMLS"
        if not scratch.exists():
            copy_script(scratch, "scripts/build-memoshi-mls.sh")
            copy_script(scratch, "scripts/lib/build-paths.sh")
            write(base / "libdir/libstd-controlled.rlib", "")
            for name, content in self.stand_ins.items():
                write(tools / name, content).chmod(0o755)
            for relative in self.outputs.values():
                write(package / relative, "old\n")
        result = execute([scratch / "scripts/build-memoshi-mls.sh"], scratch, PATH=f"{tools}:{os.environ['PATH']}",
                         STAND_IN=base, STAND_IN_FAIL=fail, MEMOSHI_MLS_BUILD_ROOT=base / "work")
        state = {name: (package / relative).read_text().strip() if (package / relative).exists() else None
                 for name, relative in self.outputs.items()}
        return result, state, package, base / "work"

    @staticmethod
    def leftovers(package):
        """Staging the script left behind: its staging directory and hidden copies beside the tracked outputs."""
        return sorted(str(path.relative_to(package)) for pattern in
                      ("Artifacts/.install.*", "Sources/MemoshiMLSNativeBindings/.*", "Generated/include/.*")
                      for path in package.glob(pattern))

    def test_a_refused_crate_stops_licence_retention_before_anything_is_written(self):
        for licence, refused in (("MIT", False), ("GPL-3.0-only", True), ("Zlib", True)):
            with self.subTest(licence=licence), tempfile.TemporaryDirectory() as directory:
                base = Path(directory).resolve()
                scratch, crate = base / "Memoshi", base / "registry/controlled-1.0.0"
                script = copy_script(scratch, "scripts/retain-memoshi-mls-licenses.py")
                copy_script(scratch, "scripts/lib/license_policy.py")
                native = scratch / "Packages/MemoshiMLS/Native"
                write(native / "Cargo.lock", "# controlled\n")
                write(crate / "LICENSE", "controlled terms\n")
                metadata = {"packages": [{"name": "controlled", "version": "1.0.0", "id": "controlled 1.0.0", "license": licence,
                                          "source": "registry+https://example.invalid/index", "repository": None,
                                          "manifest_path": str(crate / "Cargo.toml")}]}
                write(base / "metadata.json", json.dumps(metadata))
                write(base / "tools/rustup", '#!/bin/bash\ncat "$STAND_IN/metadata.json"\n').chmod(0o755)
                result = execute([sys.executable, script, "--toolchain", "stable"], scratch,
                                 PATH=f"{base / 'tools'}:{os.environ['PATH']}", STAND_IN=base)
                if refused:
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(f"controlled@1.0.0 ({licence})", result.stderr)
                    self.assertFalse((native / "Licenses").exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue((native / "Licenses/controlled-1.0.0/LICENSE").is_file())

    def test_a_failed_build_never_leaves_new_bindings_beside_the_old_binary(self):
        for step in ("xcodebuild", "licences"):
            with self.subTest(failing_step=step), tempfile.TemporaryDirectory() as directory:
                result, state, package, _ = self.build(directory, fail=step)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(state, dict.fromkeys(self.outputs, "old"))
                self.assertEqual(self.leftovers(package), [], "staging left behind")

    def test_a_framework_whose_headers_differ_from_the_generated_header_is_never_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            result, state, package, _ = self.build(directory, fail="headers")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("differ from the generated header and module map", result.stderr)
            self.assertEqual(state, dict.fromkeys(self.outputs, "old"))
            self.assertEqual(self.leftovers(package), [], "staging left behind")

    def test_the_framework_is_staged_on_the_volume_of_its_artifacts_directory(self):
        # Each install step is then a rename(2), never a copy across volumes from the build root.
        with tempfile.TemporaryDirectory() as directory:
            result, _, package, _ = self.build(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            staged = Path((Path(directory) / "xcodebuild-output").read_text().strip())
            self.assertEqual(staged.parent.parent, package / "Artifacts")

    def test_an_install_that_stops_midway_leaves_no_payload_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            # The old framework cannot be moved aside, after the tracked outputs were renamed into place.
            self.build(directory, fail="xcodebuild")
            framework = Path(directory).resolve() / "Memoshi/Packages/MemoshiMLS/Artifacts/MemoshiMLSNativeFFI.xcframework"
            framework.chmod(0o555)
            try:
                result, state, package, _ = self.build(directory)
            finally:
                framework.chmod(0o755)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state["bindings"], "new")
            self.assertEqual(state["binary"], "old")
            # No inventory claims the mixed payload, so `--check` refuses it.
            self.assertIsNone(state["manifest"])
            self.assertEqual(self.leftovers(package), [], "staging left behind")

    def test_a_successful_build_installs_bindings_header_and_binary_together(self):
        with tempfile.TemporaryDirectory() as directory:
            self.build(directory, fail="xcodebuild")
            stale = write(Path(directory).resolve() / "Memoshi/Packages/MemoshiMLS/Artifacts/MemoshiMLSNativeFFI.xcframework/stale", "old\n")
            result, state, package, _ = self.build(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state, dict.fromkeys(self.outputs, "new"))
            # The framework is replaced whole, and carries exactly the header and module map that were installed.
            self.assertFalse(stale.exists())
            framework = package / "Artifacts/MemoshiMLSNativeFFI.xcframework"
            self.assertEqual(sorted(path.name for path in (framework / "Headers").iterdir()),
                             ["MemoshiMLSNativeFFI.h", "module.modulemap"])
            self.assertEqual(sorted(path.name for path in (package / "Generated/include").iterdir()),
                             ["MemoshiMLSNativeFFI.h", "module.modulemap"])
            self.assertEqual(self.leftovers(package), [])


class RuntimeLicenceBundlingTests(unittest.TestCase):
    """D133: the retained Python licence texts are installed into the runtime and stay there in a built app."""

    table_path = "scripts/pyodide-licenses.json"

    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("memoshi_package_pyodide", ROOT / "scripts/package-pyodide.py")
        cls.packager = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.packager)
        sys.path.insert(0, str(ROOT / "scripts/lib"))
        import release_support
        cls.release_support = release_support
        cls.table = json.loads((ROOT / cls.table_path).read_text())

    def repository(self, directory):
        """A scratch repository with the table and every file it retains, so a test can change one."""
        root = Path(directory).resolve() / "repository"
        copy_script(root, self.table_path)
        for row in self.table["packages"]:
            for item in license_policy.retained_files(row):
                copy_script(root, item["path"])
        return root

    def test_packaging_installs_every_retained_file_beside_the_runtime_licences(self):
        with tempfile.TemporaryDirectory() as directory:
            root, runtime = self.repository(directory), Path(directory).resolve() / "Runtime"
            installed = self.packager.install_retained_licences(runtime, root)
            matplotlib = next(row for row in self.table["packages"] if row["package"] == "matplotlib")
            retained = license_policy.retained_files(matplotlib)
            self.assertEqual(len(installed), len(retained))
            self.assertEqual(len(retained), 17)
            base = runtime / "Licences/matplotlib/retained"
            for relative in ("LICENSE", "LICENSE_BAKOMA", "AGG24-copying", "UPSTREAM-NOTICE", "outside/humor-sans/debian-copyright",
                             "outside/freetype-2.13.3/FTL.TXT", "outside/adobe-afm/MustRead.html"):
                source = ROOT / "Packages/MemoshiApp/LicenseSources/matplotlib-3.10.8" / relative
                self.assertEqual((base / relative).read_bytes(), source.read_bytes(), relative)
            self.assertEqual(sorted(path.relative_to(runtime).as_posix() for path in runtime.rglob("*") if path.is_file()), sorted(installed))
            # A second run verifies what is there and writes nothing; a different file is never overwritten.
            self.assertEqual(self.packager.install_retained_licences(runtime, root), installed)
            (base / "LICENSE_BAKOMA").write_bytes(b"edited")
            with self.assertRaisesRegex(ValueError, "existing resource differs.*LICENSE_BAKOMA"):
                self.packager.install_retained_licences(runtime, root)
            self.assertEqual((base / "LICENSE_BAKOMA").read_bytes(), b"edited")

    def test_packaging_refuses_a_retained_file_that_is_not_the_reviewed_one(self):
        for change in ("edit", "delete"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root, runtime = self.repository(directory), Path(directory).resolve() / "Runtime"
                source = root / "Packages/MemoshiApp/LicenseSources/matplotlib-3.10.8/LICENSE_YORICK"
                source.write_bytes(b"edited") if change == "edit" else source.unlink()
                with self.assertRaisesRegex(ValueError, "retained licence file is missing or changed.*LICENSE_YORICK"):
                    self.packager.install_retained_licences(runtime, root)
                self.assertFalse(runtime.exists())

    def bundle(self, directory, name):
        """An app-shaped directory whose resource bundle holds the runtime as packaging lays it out."""
        resources = Path(directory).resolve() / name / "MemoshiApp_PyodideSpike.bundle"
        self.packager.install_retained_licences(resources / "Runtime", ROOT)
        write(resources / "Runtime/pyodide.asm.wasm", "controlled runtime")
        return resources.parent

    def test_a_built_app_passes_only_with_every_retained_text_unchanged(self):
        check = [sys.executable, ROOT / "scripts/check-pyodide-licenses.py", "--bundle"]
        with tempfile.TemporaryDirectory() as directory:
            app = self.bundle(directory, "Memoshi.app")
            self.assertEqual(self.release_support.missing_runtime_licences(app, self.table, ROOT), [])
            passed = execute(check + [app], ROOT)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            retained = app / "MemoshiApp_PyodideSpike.bundle/Runtime/Licences/matplotlib/retained"
            (retained / "LICENSE_BAKOMA").write_bytes(b"edited")
            (retained / "outside/qhull-8.0.2/COPYING.txt").unlink()
            failed = execute(check + [app], ROOT)
            self.assertEqual(failed.returncode, 1)
            for path in ("LICENSE_BAKOMA", "outside/qhull-8.0.2/COPYING.txt"):
                self.assertIn(f"Packages/MemoshiApp/LicenseSources/matplotlib-3.10.8/{path}", failed.stderr)
            # An app without the Python runtime needs none.
            empty = Path(directory) / "Other.app"
            empty.mkdir()
            self.assertEqual(execute(check + [empty], ROOT).returncode, 0)

    def test_ci_checks_the_runtime_licences_of_both_built_apps(self):
        script = (ROOT / "scripts/check-bundle.sh").read_text()
        self.assertIn('python3 scripts/check-pyodide-licenses.py --bundle "$bundle"', script)
        self.assertRegex(script, r'for bundle in "\$app" \$\{mobile_app:\+"\$mobile_app"\}; do')
        # The packaging step runs before the apps are built.
        steps = re.findall(r'^step "[^"]+" (.+)$', (ROOT / "scripts/ci.sh").read_text(), re.MULTILINE)
        self.assertLess(steps.index("python3 scripts/package-pyodide.py --allow-download"), steps.index("scripts/build-apps.sh"))


class SpikeSelfTestTests(unittest.TestCase):
    """D131: the spikes' own self-tests run in CI, so they cannot rot."""

    def test_ci_runs_every_spike_self_test_without_network_simulator_or_signing(self):
        steps = re.findall(r'^step "[^"]+" (.+)$', (ROOT / "scripts/ci.sh").read_text(), re.MULTILINE)
        self.assertIn("scripts/test-spikes.sh", steps)
        script = (ROOT / "scripts/test-spikes.sh").read_text()
        suites = sorted({path.parent.relative_to(ROOT).as_posix() for path in (ROOT / "spikes").rglob("test_*.py")})
        self.assertEqual(suites, ["spikes/S3-webkit-browser/ios-simulator", "spikes/S3-webkit-browser/no-bypass"])
        for suite in suites:
            self.assertIn(f"discover -s {suite} -p 'test_*.py'", script)
        # The Swift self-test is compiled from the app's own registry source, as its header says.
        for source in ("apps/shared/BrowserReviewProfile.swift", "apps/shared/MobileBrowserProbeRecord.swift",
                       "spikes/S3-webkit-browser/probe-record/ProbeRecordSelfTest.swift"):
            self.assertTrue((ROOT / source).is_file(), source)
            self.assertIn(source, script)
        self.assertIn("-D MEMOSHI_PROBE_RECORD_SELFTEST", script)
        commands = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
        for tool in ("xcodebuild", "simctl", "codesign", "curl", "swift package", "swift build"):
            self.assertNotIn(tool, commands)


    def step(self, directory, python=0, compiler=0, selftest=0):
        """Runs test-spikes.sh with stand-ins for python3 and the Swift compiler; nothing is compiled."""
        base = Path(directory).resolve()
        scratch, tools = base / "Memoshi", base / "tools"
        script = copy_script(scratch, "scripts/test-spikes.sh")
        copy_script(scratch, "scripts/lib/build-paths.sh")
        write(tools / "python3", '#!/bin/bash\necho "suite $6" >>"$STAND_IN/ran"\nexit "$STAND_IN_PYTHON"\n').chmod(0o755)
        # The stand-in compiler writes the program it was asked for at -o; that program is the self-test.
        write(tools / "xcrun", """#!/bin/bash
[ "$STAND_IN_COMPILER" -eq 0 ] || exit "$STAND_IN_COMPILER"
while [ "$1" != -o ]; do shift; done
printf '#!/bin/bash\\necho "self-test" >>"%s/ran"\\nexit %s\\n' "$STAND_IN" "$STAND_IN_SELFTEST" >"$2"
chmod +x "$2"
""").chmod(0o755)
        result = execute([script], scratch, PATH=f"{tools}:{os.environ['PATH']}", TMPDIR=base, STAND_IN=base,
                         STAND_IN_PYTHON=python, STAND_IN_COMPILER=compiler, STAND_IN_SELFTEST=selftest)
        ran = (base / "ran").read_text().splitlines() if (base / "ran").exists() else []
        return result.returncode, ran, sorted(path.name for path in base.glob("memoshi-probe-record.*"))

    def test_the_step_runs_the_compiled_self_test_and_fails_when_any_self_test_fails(self):
        suites = ["suite spikes/S3-webkit-browser/no-bypass", "suite spikes/S3-webkit-browser/ios-simulator"]
        with tempfile.TemporaryDirectory() as directory:
            # Compiling is not enough: the program is run, and its exit status is the step's.
            self.assertEqual(self.step(directory), (0, suites + ["self-test"], []))
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(self.step(directory, selftest=1), (1, suites + ["self-test"], []))
        with tempfile.TemporaryDirectory() as directory:
            status, ran, left = self.step(directory, compiler=1)
            self.assertEqual((status != 0, ran, left), (True, suites, []))
        with tempfile.TemporaryDirectory() as directory:
            status, ran, left = self.step(directory, python=1)
            self.assertEqual((status != 0, ran, left), (True, suites[:1], []))


class AppTestTests(unittest.TestCase):
    """The app sources' unit tests run in CI, and never inside an app the run would launch."""

    def test_ci_runs_the_app_tests_on_the_generated_project_after_the_app_builds(self):
        steps = re.findall(r'^step "[^"]+" (.+)$', (ROOT / "scripts/ci.sh").read_text(), re.MULTILINE)
        tests = steps.index("scripts/test-apps.sh")
        self.assertLess(steps.index("scripts/generate-project.sh"), tests)
        self.assertLess(steps.index("scripts/build-apps.sh"), tests)

    def test_app_test_bundles_have_no_host_app(self):
        project = (ROOT / "apps/mac/project.yml").read_text()
        self.assertNotIn("TEST_HOST", project)
        for target in ("MemoshiTests", "MemoshiMobileTests"):
            block = re.search(rf"^  {target}:\n((?:    .*\n|\n)*)", project, re.MULTILINE)
            self.assertIsNotNone(block, target)
            self.assertIn("type: bundle.unit-test", block[1])
            # A target dependency on an app would make XcodeGen host the bundle in it.
            self.assertNotRegex(block[1], r"- target:")


class SignInFlowTests(unittest.TestCase):
    def scratch(self, directory):
        scratch = Path(directory).resolve() / "Memoshi"
        for path in sorted((ROOT / "scripts").glob("*")) + sorted((ROOT / "scripts/lib").glob("*")) \
                + sorted((ROOT / ".github/workflows").glob("*")) + [ROOT / "apps/mac/project.yml"] \
                + sorted((ROOT / "Packages").glob("*/Package.swift")) + sorted((ROOT / "Packages").glob("*/Package.resolved")):
            if path.is_file():
                copy_script(scratch, path.relative_to(ROOT))
        tool = write(Path(directory).resolve() / "Fixture.app/tool", "controlled code\n")
        tool.chmod(0o755)
        return scratch, tool.parent

    def test_release_entry_points_cannot_enable_the_subscription_sign_in_trait(self):
        for relative in ("scripts/release.py", "scripts/lib/release_support.py"):
            with self.subTest(entry_point=relative), tempfile.TemporaryDirectory() as directory:
                scratch, app = self.scratch(directory)
                script = scratch / "scripts/check-signin-flows.sh"
                clean = execute([script, app], scratch)
                self.assertEqual(clean.returncode, 0, clean.stderr)
                with (scratch / relative).open("a") as stream:
                    stream.write('\nEXTRA = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS=SubscriptionLogins"]\n')
                enabled = execute([script, app], scratch)
                self.assertEqual(enabled.returncode, 1)
                self.assertIn(f"package trait enabled: {relative}:", enabled.stderr)

    def test_an_app_passed_as_an_argument_is_scanned_for_restricted_client_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch, app = self.scratch(directory)
            (app / "tool").write_text("controlled code 17e5f671-d194-4dfb-9706-5516cb48c098\n")
            found = execute([scratch / "scripts/check-signin-flows.sh", app], scratch)
            self.assertEqual(found.returncode, 1)
            self.assertIn("restricted subscription client ID 17e5f671-d194-4dfb-9706-5516cb48c098", found.stderr)


class BoundaryLintTests(unittest.TestCase):
    def lint(self, files, unreadable=()):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory).resolve()
            copy_script(scratch, "scripts/lint-boundaries.sh")
            copy_script(scratch, "scripts/lib/swift-sources.sh")
            for relative, content in files.items():
                write(scratch / relative, content)
            for relative in unreadable:
                (scratch / relative).chmod(0)
            try:
                return execute([scratch / "scripts/lint-boundaries.sh"], scratch)
            finally:
                for relative in unreadable:
                    (scratch / relative).chmod(0o600)

    def test_the_runtime_directory_may_import_but_never_re_export_pi_modules(self):
        runtime = "Packages/MemoshiCore/Sources/Runtime/Engine.swift"
        allowed = self.lint({runtime: "import PiAI\n@preconcurrency import PiCore\n@_exported import Foundation\n"})
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        for declaration in ("@_exported import PiAI", "  @_exported @preconcurrency public import PiCore",
                            "@preconcurrency @_exported import struct PiAgent.Agent"):
            with self.subTest(declaration=declaration):
                exported = self.lint({runtime: f"import Foundation\n{declaration}\n"})
                self.assertEqual(exported.returncode, 1)
                self.assertIn(f"{runtime}:2: error:", exported.stderr)
                self.assertIn("1 module boundary violation", exported.stderr)
        outside = self.lint({"Packages/MemoshiCore/Sources/Store/Store.swift": "@_exported import PiAI\n"})
        self.assertEqual(outside.returncode, 1)
        self.assertIn("1 module boundary violation", outside.stderr)

    def test_nothing_imports_the_memoshid_executable_module(self):
        for declaration in ("import memoshid", "@testable import memoshid", "import struct memoshid.Daemon"):
            with self.subTest(declaration=declaration):
                found = self.lint({"Packages/MemoshiDaemon/Tests/DaemonTests/Tests.swift": f"import Testing\n{declaration}\n"})
                self.assertEqual(found.returncode, 1)
                self.assertIn("Tests.swift:2: error: no target may import memoshid's executable module", found.stderr)
        self.assertEqual(self.lint({"Sources/Other.swift": "import memoshidSupport\n"}).returncode, 0)

    @unittest.skipIf(os.geteuid() == 0, "root reads a file whatever its mode")
    def test_an_unreadable_source_fails_the_lint(self):
        store = "Packages/MemoshiCore/Sources/Store/Store.swift"
        result = self.lint({store: "import PiAI\n", "Sources/Other.swift": "import Foundation\n"}, unreadable=[store])
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(f"{store}: error: could not read", result.stderr)
        self.assertNotIn("ok:", result.stdout)

    def test_a_tree_without_swift_sources_fails_the_lint(self):
        result = self.lint({"README.md": "no Swift here\n"})
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("no Swift sources", result.stderr)

    def test_the_lint_names_every_module_of_the_pinned_pi_swift_manifest(self):
        pin = dict(re.findall(r"^(PI_SWIFT_[A-Z]+)=(\S+)$", (ROOT / "scripts/lib/pi-swift-pin.sh").read_text(), re.M))
        manifests = [ROOT / pin["PI_SWIFT_CHECKOUT"] / "Package.swift",
                     ROOT / pin["PI_SWIFT_CHECKOUT"] / "Vendor/SwiftBashParser/Package.swift"]
        if not all(path.is_file() for path in manifests):
            self.skipTest("the pinned Pi_Swift checkout is absent; scripts/check-prerequisites.sh creates it")
        declared = set()
        for path in manifests:
            for kind, name in re.findall(r'\.(target|executableTarget|systemLibrary|binaryTarget|macro|plugin)\(\s*name:\s*"([^"]+)"',
                                         path.read_text()):
                declared.add(name.replace("-", "_"))
        listed = re.search(r"^pi_swift_module_list=\(\n(.*?)^\)$", (ROOT / "scripts/lint-boundaries.sh").read_text(), re.M | re.S)
        self.assertEqual(set(listed[1].split()), declared)


class ProjectLockTests(unittest.TestCase):
    """Xcode reads one workspace-level lock inside the generated project, never a package's own."""

    lock = "apps/mac/Memoshi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

    def generate(self, directory, pins):
        scratch = Path(directory).resolve() / "Memoshi"
        copy_script(scratch, "scripts/generate-project.sh")
        write(scratch / "apps/mac/project.yml", "name: Memoshi\n")
        for package, entries in pins.items():
            write(scratch / f"Packages/{package}/Package.resolved",
                  json.dumps({"originHash": "0" * 64, "pins": entries, "version": 3}))
        # XcodeGen itself is not under test: a stand-in creates the project directory it would.
        tools = Path(directory).resolve() / "tools"
        stand_in = write(tools / "xcodegen", '#!/bin/bash\nmkdir -p apps/mac/Memoshi.xcodeproj\n')
        stand_in.chmod(0o755)
        result = execute([scratch / "scripts/generate-project.sh"], scratch, PATH=f"{tools}:{os.environ['PATH']}")
        return result, scratch / self.lock

    @staticmethod
    def pin(identity, revision, version=None, location=None):
        state = {"revision": revision, **({"version": version} if version else {})}
        return {"identity": identity, "kind": "remoteSourceControl",
                "location": location or f"https://example.invalid/{identity}", "state": state}

    def test_generated_project_is_locked_to_the_union_of_the_committed_package_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            shared = self.pin("swift-collections", "a" * 40, "1.7.4")
            result, lock = self.generate(directory, {
                "MemoshiCore": [shared, self.pin("swift-nio", "b" * 40, "2.104.0")],
                "MemoshiProtocol": [self.pin("swift-syntax", "c" * 40, "604.0.0"),
                                    {**shared, "location": shared["location"] + ".git"}],
            })
            self.assertEqual(result.returncode, 0, result.stderr)
            written = json.loads(lock.read_text())
            self.assertEqual([(item["identity"], item["state"]) for item in written["pins"]],
                             [("swift-collections", {"revision": "a" * 40, "version": "1.7.4"}),
                              ("swift-nio", {"revision": "b" * 40, "version": "2.104.0"}),
                              ("swift-syntax", {"revision": "c" * 40, "version": "604.0.0"})])
            # Locations are kept as committed.
            self.assertEqual(written["pins"][0]["location"], shared["location"])
            self.assertNotIn("originHash", written)

    def test_packages_that_disagree_on_a_pin_stop_project_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            result, lock = self.generate(directory, {
                "MemoshiCore": [self.pin("swift-collections", "a" * 40, "1.7.4")],
                "MemoshiIPC": [self.pin("swift-collections", "d" * 40, "1.7.5")],
            })
            self.assertEqual(result.returncode, 1)
            self.assertIn("disagree on the pin for swift-collections", result.stderr)
            self.assertFalse(lock.exists() or Path(f"{lock}.tmp").exists())

    def test_committed_package_pins_agree_and_every_build_refuses_to_resolve_past_them(self):
        pins = {}
        for resolved in sorted((ROOT / "Packages").glob("*/Package.resolved")):
            for item in json.loads(resolved.read_text())["pins"]:
                self.assertEqual(pins.setdefault(item["identity"], item["state"]), item["state"], item["identity"])
        # Pi_Swift is a path dependency on the checkout scripts/lib/pi-swift-pin.sh names, so no
        # package pins it; check-prerequisites.sh pins that checkout instead.
        self.assertNotIn("pi_swift", pins)
        flag = "-disableAutomaticPackageResolution"
        builds = re.findall(r"^xcodebuild build\b(?:[^\n]*\\\n)*[^\n]*", (ROOT / "scripts/build-apps.sh").read_text(), re.MULTILINE)
        self.assertEqual(len(builds), 2)
        for command in builds:
            self.assertIn(flag, command)
        tests = re.findall(r"^xcodebuild test\b(?:[^\n]*\\\n)*[^\n]*", (ROOT / "scripts/test-apps.sh").read_text(), re.MULTILINE)
        self.assertEqual(len(tests), 2)
        for command in tests:
            self.assertIn(flag, command)
        archive = re.search(r'run\(\["/usr/bin/xcodebuild", "archive".*?label="Release-archive"\)',
                            (ROOT / "scripts/release.py").read_text(), re.DOTALL)
        self.assertIn(f'"{flag}"', archive[0])
        self.assertRegex((ROOT / "scripts/scan-licenses.sh").read_text(),
                         r"swift package [^\n]*--disable-automatic-resolution[^\n]* resolve\n")


class LicensePolicyTests(unittest.TestCase):
    """D126: one accepted list (MIT, Apache-2.0, BSD, ISC) for every dependency."""

    def test_an_expression_is_accepted_only_through_licences_on_the_list(self):
        for expression in ("MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "MIT AND ISC",
                           "MIT OR Apache-2.0", "Apache-2.0 OR MIT", "MIT/Apache-2.0", "Unlicense OR MIT",
                           "Apache-2.0 OR BSL-1.0", "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT",
                           "MIT OR Apache-2.0 OR LGPL-2.1-or-later", "MIT OR GPL-3.0",
                           "GPL-3.0-only OR (MIT AND BSD-2-Clause)"):
            with self.subTest(expression=expression):
                self.assertTrue(license_policy.accepted(expression))
        for expression in ("GPL-3.0-only", "AGPL-3.0-only", "LGPL-2.1-or-later", "MIT AND GPL-3.0-only",
                           "GPL-2.0-only WITH Classpath-exception-2.0", "PolyForm-Noncommercial-1.0.0",
                           "GPL-3.0/AGPL-3.0", "MPL-2.0", "Unicode-3.0", "(MIT OR Apache-2.0) AND Unicode-3.0",
                           "Unlicense", "BSL-1.0", "Zlib", "0BSD", "CC0-1.0", "MIT-CMU", "BSD-4-Clause",
                           "Apache-2.0 WITH LLVM-exception", "MIT AND Zlib", "mit", "LicenseRef-unstated"):
            with self.subTest(expression=expression):
                self.assertFalse(license_policy.accepted(expression))

    def test_an_absent_or_malformed_expression_is_never_read_as_accepted(self):
        for expression in (None, "", "   ", "MIT OR", "(MIT", "MIT)", "MIT Apache-2.0", "OR MIT", "MIT WITH",
                           "MIT AND AND ISC", "()", "MIT OR (OR ISC)"):
            with self.subTest(expression=expression), self.assertRaises(ValueError):
                license_policy.accepted(expression)

    @staticmethod
    def crate(name, license):
        return {"name": name, "version": "1.0.0", "license": license}

    def test_the_two_exceptions_hold_for_the_named_crates_only(self):
        uniffi = ("uniffi", "uniffi_bindgen", "uniffi_core", "uniffi_internal_macros", "uniffi_macros",
                  "uniffi_meta", "uniffi_pipeline", "uniffi_udl")
        named = [self.crate(name, "MPL-2.0") for name in uniffi]
        named.append(self.crate("unicode-ident", "(MIT OR Apache-2.0) AND Unicode-3.0"))
        self.assertEqual(license_policy.unaccepted_crates(named), [])
        for name, license in (("serde", "MPL-2.0"), ("uniffi_later_addition", "MPL-2.0"), ("unicode-ident", "MPL-2.0"),
                              ("uniffi", "Unicode-3.0"), ("unicode-width", "(MIT OR Apache-2.0) AND Unicode-3.0")):
            with self.subTest(crate=name, license=license):
                self.assertEqual(license_policy.unaccepted_crates([self.crate(name, license)]), [f"{name}@1.0.0 ({license})"])

    def test_a_crate_without_a_readable_licence_fails_like_an_unlisted_one(self):
        crates = [self.crate("absent", None), self.crate("malformed", "MIT OR"), self.crate("fine", "MIT")]
        self.assertEqual(license_policy.unaccepted_crates(crates),
                         ["absent@1.0.0 (no readable licence expression)", "malformed@1.0.0 (no readable licence expression)"])

    def test_the_retained_cargo_inventory_is_checked_by_the_payload_manifest(self):
        inventory = json.loads((ROOT / "Packages/MemoshiMLS/Native/Licenses/manifest.json").read_text())
        self.assertEqual(license_policy.unaccepted_crates(inventory["packages"]), [])
        added = inventory["packages"] + [self.crate("controlled-gpl-crate", "GPL-3.0-only"), self.crate("controlled-zlib-crate", "Zlib")]
        self.assertEqual(license_policy.unaccepted_crates(added),
                         ["controlled-gpl-crate@1.0.0 (GPL-3.0-only)", "controlled-zlib-crate@1.0.0 (Zlib)"])
        # Both the MLS build step and the licence scan (--check) run this script's inventory check.
        for licence, refused in (("MIT", False), ("GPL-3.0-only", True)):
            for mode in ([], ["--check"]):
                with self.subTest(licence=licence, mode=mode), tempfile.TemporaryDirectory() as directory:
                    result, written = self.payload_manifest(Path(directory).resolve(), licence, mode)
                    if refused:
                        self.assertEqual(result.returncode, 1)
                        self.assertIn("does not cover: controlled@1.0.0 (GPL-3.0-only)", result.stderr)
                        self.assertFalse(written)
                    elif mode:
                        # The licences pass; only the absent payload inventory is drift.
                        self.assertIn("MLS payload/source inventory drifted", result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertTrue(written)

    @staticmethod
    def payload_manifest(base, licence, mode):
        """Runs memoshi-mls-payload-manifest.py on a controlled MLS package with stand-in tools."""
        scratch = base / "Memoshi"
        for relative in ("scripts/memoshi-mls-payload-manifest.py", "scripts/lib/license_policy.py",
                         "scripts/build-memoshi-mls.sh", "scripts/retain-memoshi-mls-licenses.py"):
            copy_script(scratch, relative)
        package = scratch / "Packages/MemoshiMLS"
        for relative in ("Package.swift", "Native/PROVENANCE.json", "Native/Cargo.toml", "Native/Cargo.lock",
                         "Sources/MemoshiMLS/MLS.swift", "Artifacts/MemoshiMLSNativeFFI.xcframework/library",
                         "Sources/MemoshiMLSNativeBindings/Bindings.swift", "Generated/include/module.modulemap",
                         "Native/Licenses/controlled-1.0.0/LICENSE"):
            write(package / relative, f"controlled {relative}\n")
        crate = {"name": "controlled", "version": "1.0.0", "source": "registry+https://example.invalid/index", "license": licence}
        licence_file = package / "Native/Licenses/controlled-1.0.0/LICENSE"
        write(package / "Native/Licenses/manifest.json", json.dumps({
            "format": 1, "cargo_lock_sha256": hashlib.sha256((package / "Native/Cargo.lock").read_bytes()).hexdigest(),
            "packages": [{**crate, "files": [{"path": "controlled-1.0.0/LICENSE",
                                              "sha256": hashlib.sha256(licence_file.read_bytes()).hexdigest()}]}]}))
        write(base / "metadata.json", json.dumps({"packages": [crate]}))
        tools = base / "tools"
        write(tools / "rustup", '#!/bin/bash\ncase "$3" in\n  rustc) echo "rustc 1.97.0 (controlled)" ;;\n'
              '  cargo) cat "$STAND_IN/metadata.json" ;;\n  *) exit 64 ;;\nesac\n').chmod(0o755)
        write(tools / "xcrun", "#!/bin/bash\necho controlled-swift\n").chmod(0o755)
        write(tools / "xcodebuild", "#!/bin/bash\necho controlled-xcode\n").chmod(0o755)
        result = execute([sys.executable, scratch / "scripts/memoshi-mls-payload-manifest.py", "--toolchain", "1.97.0"] + mode,
                         scratch, PATH=f"{tools}:{os.environ['PATH']}", STAND_IN=base)
        return result, (package / "Artifacts/payload-manifest.json").is_file()


class PyodideLicenseTableTests(unittest.TestCase):
    """D126: a reviewed row for every Python package in the packaged Pyodide runtime."""

    table_path = "scripts/pyodide-licenses.json"
    manifest_path = "Packages/MemoshiApp/Sources/PyodideSpike/Resources/Runtime/manifest.json"
    # D126: the user accepted these four packages by name; the accepted list itself did not grow.
    # The checker holds the sets, so a row cannot grant itself an exception.
    exceptions = {
        "matplotlib": {"LicenseRef-Matplotlib", "Bitstream-Vera", "OFL-1.1", "LicenseRef-BaKoMa", "LicenseRef-Yorick",
                       "CC0-1.0", "LicenseRef-AGG-2.4", "Qhull", "FTL", "LicenseRef-Adobe-AFM", "LicenseRef-Adobe-Utopia"},
        "numpy": {"0BSD", "CC0-1.0", "Zlib"},
        "pillow": {"MIT-CMU"},
        "scipy": {"Qhull"},
    }
    # Parts of matplotlib for which no permission evidence was found. The owner accepted exactly
    # these 37 files (D126); the checker, not the row, holds them by path and SHA-256.
    unevidenced_parts = ["35 Adobe font-metric files for the Adobe base 35 fonts", "2 Adobe font-metric files for Helvetica Light"]
    sentence = "matplotlib: 37 files accepted without permission evidence by the owner's decision (D126)"
    refusal = "the files accepted without permission evidence are not exactly the ones the owner's decision (D126) names"

    def setUp(self):
        self.table = json.loads((ROOT / self.table_path).read_text())
        self.manifest = json.loads((ROOT / self.manifest_path).read_text())
        self.root = ROOT

    def problems(self):
        return license_policy.pyodide_table_problems(self.table, self.manifest, self.root)

    def row(self, name):
        return next(item for item in self.table["packages"] if item["package"] == name)

    def packaged(self, name):
        return next(item for item in self.manifest["packages"] if item["name"] == name)

    def part(self, name):
        return next(item for item in self.row("matplotlib")["withoutLicenceText"] if item["part"] == name)

    def scratch_root(self, directory):
        """A copy of every file the table retains, so a test can change one."""
        self.root = Path(directory).resolve()
        for package in self.table["packages"]:
            for item in license_policy.retained_files(package):
                copy_script(self.root, item["path"])

    def test_every_packaged_package_has_a_row_pinned_to_its_version_and_licence_files(self):
        self.assertEqual(sorted(item["package"] for item in self.table["packages"]),
                         sorted(item["name"] for item in self.manifest["packages"]))
        digests = {item["path"]: item["sha256"] for item in self.manifest["files"]}
        for row in self.table["packages"]:
            with self.subTest(package=row["package"]):
                evidence = {item["path"]: item["sha256"] for item in row["evidence"]}
                self.assertLessEqual(set(self.packaged(row["package"])["licences"]), set(evidence))
                self.assertEqual(evidence, {path: digests[path] for path in evidence})
                self.assertTrue(all(item["reading"].strip() for item in row["evidence"]))

    def test_the_checked_in_table_passes_and_says_what_was_accepted_without_evidence(self):
        self.assertEqual(self.problems(), [])
        self.assertEqual({row["verdict"] for row in self.table["packages"]}, {"accepted"})
        self.assertEqual(license_policy.accepted_without_evidence(self.table), [self.sentence])
        matplotlib = self.row("matplotlib")
        self.assertEqual(matplotlib["acceptedWithoutEvidence"],
                         {"decision": "accepted without permission evidence by the owner's decision (D126)", "files": 37})
        for name in self.unevidenced_parts:
            part = self.part(name)
            self.assertEqual((part["verdict"], part["decision"]),
                             ("accepted-without-evidence", "accepted without permission evidence by the owner's decision (D126)"))
            # No licence is claimed for a file without one.
            self.assertNotIn("licence", part)
        # The scan prints the sentence with the count.
        scanned = execute([sys.executable, ROOT / "scripts/check-pyodide-licenses.py"], ROOT)
        self.assertEqual(scanned.returncode, 0, scanned.stderr)
        self.assertIn(self.sentence, scanned.stdout)

    def test_the_owner_exception_is_held_by_the_checker_for_exactly_37_files_of_one_package(self):
        held = license_policy.PYODIDE_ACCEPTED_WITHOUT_EVIDENCE
        self.assertEqual(list(held), ["matplotlib"])
        files = held["matplotlib"]["files"]
        self.assertEqual(len(files), 37)
        self.assertTrue(all(path.startswith("matplotlib/mpl-data/fonts/afm/") and path.endswith(".afm") and len(digest) == 64
                            for path, digest in files.items()))
        digests = {item["path"]: item["sha256"] for item in self.manifest["files"]}
        self.assertEqual(digests[held["matplotlib"]["wheel"]], held["matplotlib"]["wheelSha256"])
        listed = {item["path"]: item["sha256"] for name in self.unevidenced_parts for item in self.part(name)["files"]}
        self.assertEqual(listed, files)

        def changed(change):
            self.setUp()
            change()
            return self.problems()

        base35, light = (lambda: self.part(self.unevidenced_parts[0])), (lambda: self.part(self.unevidenced_parts[1]))
        refused = [f"matplotlib: {self.refusal}"]
        # A 38th file, a changed digest, a file left out or listed twice: the exception no longer holds.
        self.assertEqual(changed(lambda: light()["files"].append(
            {"path": "matplotlib/mpl-data/fonts/afm/putr8a.afm", "sha256": "0" * 64})), refused)
        self.assertEqual(changed(lambda: base35()["files"][0].update(sha256="0" * 64)), refused)
        self.assertEqual(changed(lambda: base35()["files"].pop()), refused)
        self.assertEqual(changed(lambda: light()["files"].append(dict(light()["files"][0]))), refused)
        self.assertEqual(changed(lambda: self.row("matplotlib")["withoutLicenceText"].remove(light())), refused)
        # Another wheel build is another set of files, even at the same version.
        wheel = held["matplotlib"]["wheel"]
        self.assertIn(f"matplotlib: {self.refusal}", changed(
            lambda: next(item for item in self.manifest["files"] if item["path"] == wheel).update(sha256="0" * 64)))
        # No other package can use it, with or without files, and no row can claim it for other parts.
        for files_claimed in ([], [dict(item) for item in light()["files"]]):
            self.assertEqual(changed(lambda: self.row("six").update(withoutLicenceText=[
                {"part": "anything", "verdict": "accepted-without-evidence", "files": files_claimed}])), [f"six: {self.refusal}"])
        self.assertEqual(changed(lambda: self.part("Humor-Sans.ttf").update(verdict="accepted-without-evidence", files=[])), refused)

    def test_the_held_digests_are_the_bytes_in_the_packaged_wheel(self):
        held = license_policy.PYODIDE_ACCEPTED_WITHOUT_EVIDENCE["matplotlib"]
        wheel = (ROOT / self.manifest_path).parent / held["wheel"]
        if not wheel.is_file():
            self.skipTest("the packaged runtime is not present; scripts/package-pyodide.py recreates it")
        self.assertEqual(hashlib.sha256(wheel.read_bytes()).hexdigest(), held["wheelSha256"])
        with zipfile.ZipFile(wheel) as archive:
            metrics = {name: hashlib.sha256(archive.read(name)).hexdigest()
                       for name in archive.namelist() if name.startswith("matplotlib/mpl-data/fonts/afm/")}
        self.assertEqual({path: metrics.get(path) for path in held["files"]}, held["files"])
        # The directory holds nothing else without a retained text: five AMS files and four Utopia files.
        others = sorted(Path(name).name for name in set(metrics) - set(held["files"]))
        self.assertEqual(others, ["cmex10.afm", "cmmi10.afm", "cmr10.afm", "cmsy10.afm", "cmtt10.afm",
                                  "putb8a.afm", "putbi8a.afm", "putr8a.afm", "putri8a.afm"])

    def test_the_named_exceptions_are_held_by_the_checker_not_by_the_row(self):
        self.assertEqual({name: set(licences) for name, licences in license_policy.PYODIDE_EXCEPTIONS.items()}, self.exceptions)
        # The table states the same sets for the reader, and every licence in an expression is listed.
        self.assertEqual({row["package"]: set(row["exceptions"]["licences"]) for row in self.table["packages"] if "exceptions" in row},
                         self.exceptions)
        for row in self.table["packages"]:
            self.assertEqual(license_policy.accepted(row["license"]), row["package"] not in self.exceptions, row["package"])
            self.assertTrue(license_policy.accepted(row["license"], self.exceptions.get(row["package"], ())), row["package"])
        granted = "the row's exceptions are not the ones D126 names for this package"
        for change in ({"licences": ["Zlib"]}, {"licences": "0BSD, Zlib, CC0-1.0"}, {"licences": ["0BSD", "Zlib"]}):
            with self.subTest(change=change):
                self.setUp()
                self.row("six").update(license="Zlib", exceptions={"decision": "self-declared", "licences": ["Zlib"]})
                self.row("numpy")["exceptions"] = {"decision": "edited", **change}
                self.assertEqual(self.problems(), [f"numpy: {granted}", f"six: {granted}",
                                                   "six: marked accepted, but Zlib is not on the accepted list"])
        self.setUp()
        self.row("numpy")["license"] += " AND MPL-2.0"
        self.assertEqual(len(self.problems()), 1)

    def test_a_retained_file_that_is_missing_or_changed_fails(self):
        retained = self.row("matplotlib")["retained"]
        self.assertEqual(sorted(Path(item["path"]).name for item in retained["texts"]),
                         ["AGG24-copying", "LICENSE", "LICENSE_AMSFONTS", "LICENSE_BAKOMA", "LICENSE_COLORBREWER",
                          "LICENSE_JSXTOOLS_RESIZE_OBSERVER", "LICENSE_SOLARIZED", "LICENSE_YORICK"])
        source = retained["source"]
        self.assertEqual((source["version"], len(source["sha256"]), source["url"].startswith("https://files.pythonhosted.org/")),
                         ("3.10.8", 64, True))
        outside = [item for part in self.row("matplotlib")["withoutLicenceText"] for item in part["evidence"]]
        for item in outside:
            self.assertTrue(item["url"].startswith("https://") and item["retrieved"] == "2026-11-13" and item["shows"].strip(), item["path"])
        for kind, item in (("retained licence text", retained["texts"][1]), ("retained notice", retained["notice"]),
                           ("outside evidence", self.part("Humor-Sans.ttf")["evidence"][0])):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                self.scratch_root(directory)
                self.assertEqual(self.problems(), [])
                target = self.root / item["path"]
                failure = [f"matplotlib: {item['path']} is missing or changed"]
                original = target.read_bytes()
                target.write_bytes(original + b"\n")
                self.assertEqual(self.problems(), failure)
                target.unlink()
                self.assertEqual(self.problems(), failure)
                target.symlink_to(ROOT / item["path"])
                self.assertEqual(self.problems(), failure)
                target.unlink()
                target.write_bytes(original)
                self.assertEqual(self.problems(), [])
                saved = item["path"]
                item["path"] = "../" + saved
                self.assertEqual(self.problems(), [f"matplotlib: ../{saved} is missing or changed"])
                item["path"] = saved

    def test_a_part_without_a_licence_text_passes_only_with_accepted_outside_evidence(self):
        self.assertEqual(self.problems(), [])
        part = self.part("Humor-Sans.ttf")
        self.assertEqual(part["identicalTo"]["sha256"], "2ded6a27448c9ed30aaff177744e2bcf1e52e0aab018b2a8be64565df633318f")
        failure = ["matplotlib: Humor-Sans.ttf: no accepted permission evidence"]
        evidence = part.pop("evidence")
        self.assertEqual(self.problems(), failure)
        part["evidence"] = []
        self.assertEqual(self.problems(), failure)
        part["evidence"] = evidence
        part["verdict"] = "review"
        self.assertEqual(self.problems(), failure)
        del part["verdict"]
        self.assertEqual(self.problems(), failure)
        # Without the owner's decision the two unevidenced parts are refused like any other.
        self.setUp()
        for name in self.unevidenced_parts:
            self.part(name)["verdict"] = "review"
        self.assertEqual(self.problems(), [f"matplotlib: {name}: no accepted permission evidence" for name in self.unevidenced_parts]
                         + [f"matplotlib: {self.refusal}"])

    def test_a_missing_row_a_changed_version_or_changed_evidence_fails(self):
        def added(change):
            self.setUp()
            change()
            return self.problems()

        self.assertEqual(added(lambda: self.table["packages"].remove(self.row("six"))),
                         ["six 1.17.0: no reviewed licence row"])
        self.assertEqual(added(lambda: self.packaged("six").update(version="1.18.0")),
                         ["six: reviewed at 1.17.0, packaged at 1.18.0"])
        licence = "Licences/six/six-1.17.0.dist-info/LICENSE"

        def change_digest():
            next(item for item in self.manifest["files"] if item["path"] == licence)["sha256"] = "0" * 64
        self.assertEqual(added(change_digest), [f"six: {licence} is not the file that was reviewed"])
        self.assertEqual(added(lambda: self.packaged("six")["licences"].append("Licences/six/COPYING.GPL")),
                         ["six: Licences/six/COPYING.GPL was not reviewed"])
        self.assertEqual(added(lambda: self.table["packages"].append({**self.row("six"), "package": "left-over"})),
                         ["left-over: row for a package the runtime does not ship"])
        self.assertEqual(added(lambda: self.table["packages"].append(dict(self.row("six")))), ["six: more than one row"])

    def test_a_row_cannot_accept_a_licence_outside_the_accepted_list(self):
        def added(**change):
            self.setUp()
            self.row("six").update(change)
            return self.problems()

        self.assertEqual(added(license="MIT-CMU"), ["six: marked accepted, but MIT-CMU is not on the accepted list"])
        self.assertEqual(added(verdict="review"), ["six 1.17.0: verdict review (MIT)"])
        self.assertEqual(added(license="Zlib", verdict="not-accepted"), ["six 1.17.0: verdict not-accepted (Zlib)"])
        self.assertEqual(added(verdict="not-accepted"), ["six: marked not-accepted, but MIT is on the accepted list"])
        self.assertEqual(added(verdict="waived"), ["six: unknown verdict waived"])
        self.assertEqual(added(license="MIT OR"), ["six: no readable licence expression"])

    def test_the_licence_scan_runs_the_table_check(self):
        self.assertIn("python3 scripts/check-pyodide-licenses.py", (ROOT / "scripts/scan-licenses.sh").read_text())
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory).resolve()
            script = copy_script(scratch, "scripts/check-pyodide-licenses.py")
            copy_script(scratch, "scripts/lib/license_policy.py")
            six, files = self.packaged("six"), self.manifest["files"]
            manifest = {"packages": [six], "files": [item for item in files if item["path"] in six["licences"]]}
            write(scratch / self.manifest_path, json.dumps(manifest))
            table = write(scratch / self.table_path, json.dumps({"packages": [self.row("six")]}))
            passed = execute([sys.executable, script], scratch)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            table.write_text(json.dumps({"packages": []}))
            failed = execute([sys.executable, script], scratch)
            self.assertEqual(failed.returncode, 1)
            self.assertIn("six 1.17.0: no reviewed licence row", failed.stderr)


if __name__ == "__main__":
    unittest.main()
