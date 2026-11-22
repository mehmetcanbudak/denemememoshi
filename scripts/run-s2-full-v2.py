#!/usr/bin/env python3
"""Build memoshi-qualification in the canonical build root and run the full S2 batch once
(`s2 --load --real-expiry`) in an owned process group; write run.json.

Usage: run-s2-full-v2.py <new-run-dir> <repo> <0700-build-root> <absent-work-dir> [<allowed untracked path>]

The tree must be clean, or its `git status --short` must be exactly the one untracked file named
last (another session's report, used by no build step). Any other change stops the run before
the run directory is created. The status is recorded verbatim at start and end, and whether it
changed. Commands run through run_owned (scripts/lib/owned_process.py) with a credential-free
environment. The build uses scripts/lib/build-paths.sh and the flags scripts/test-packages.sh
uses, so it reuses what the canonical CI run built.

This script takes no build lock itself. Run it under the lock every other build of the build
root takes, so that nothing else builds meanwhile; the s2-full runs used
../evidence/2026-11-07-memoshi-engineering/build-lock.py (outside the repository), which holds
$MEMOSHI_BUILD_ROOT/.memoshi-build.lock.

History: version 2 (2026-11-14, for s2-full-03) of run-s2-full.py, which stays in the evidence
folder ../evidence/2026-11-13-memoshi-canonical-s2/ with this script's original copy. Moved into
scripts/ on 2026-11-16. Since 2026-11-18 it imports run_owned from scripts/lib, checks the tree
before it creates the run directory, and resolves the work directory.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(sys.argv[1]).resolve()
repo = str(Path(sys.argv[2]).resolve(strict=True))
build_root = str(Path(sys.argv[3]).resolve(strict=True))
work = Path(sys.argv[4]).resolve()
allowed_status = f'?? {sys.argv[5]}\n' if len(sys.argv) > 5 else ''
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / 'lib'))
from owned_process import run_owned  # noqa: E402


def git(*arguments):
    return subprocess.run(['git', '-C', repo, *arguments], capture_output=True, text=True,
                          check=True).stdout


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load():
    yes = subprocess.run(['/usr/bin/pgrep', '-x', 'yes'], capture_output=True, text=True).stdout.split()
    return {'loadAverage': list(os.getloadavg()), 'yesProcesses': len(yes)}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


head = git('rev-parse', 'HEAD').strip()
dirty = git('status', '--short')
if dirty not in ('', allowed_status):
    raise SystemExit('tree has changes besides the allowed untracked file:\n' + dirty)
root.mkdir(mode=0o700)
allowed = ('PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TMPDIR', 'DEVELOPER_DIR')
environment = {key: os.environ[key] for key in allowed if key in os.environ}
environment.update(GIT_TERMINAL_PROMPT='0')

build_script = r'''set -euo pipefail
source scripts/lib/build-paths.sh
memoshi_package_paths Packages/MemoshiDaemon
echo "swift build ${swiftpm_args[*]} --disable-automatic-resolution --jobs 2 --product memoshi-qualification"
swift build "${swiftpm_args[@]}" --disable-automatic-resolution --jobs 2 --product memoshi-qualification
echo "BIN_PATH=$(swift build "${swiftpm_args[@]}" --disable-automatic-resolution --show-bin-path)"
'''
build_command = ['/usr/bin/env', 'MEMOSHI_BUILD_ROOT=' + build_root, 'MEMOSHI_BUILD_JOBS=2',
                 '/bin/bash', '-c', build_script]
build_started = now()
build_begin = time.monotonic()
with (root / 'build.txt').open('xb') as stream:
    build = run_owned(build_command, cwd=repo, env=environment, stdout=stream, timeout=3600)
build_seconds = time.monotonic() - build_begin
receipt = {'cwd': repo, 'commit': head, 'treeCleanAtStart': dirty == '', 'gitStatusShortAtStart': dirty,
           'credentialEnvironmentInherited': False,
           'build': {'commandArgv': build_command[:-1] + ['<build script, see scripts/run-s2-full-v2.py>'],
                     'startedAt': build_started, 'wallSeconds': build_seconds, **build}}
binary = None
for line in (root / 'build.txt').read_text(errors='replace').splitlines():
    if line.startswith('BIN_PATH='):
        binary = line[len('BIN_PATH='):] + '/memoshi-qualification'
if build['wrapperStatus'] != 0 or binary is None or not Path(binary).is_file():
    receipt['exitCode'] = build['wrapperStatus'] or 70
    receipt['failedStep'] = 'build'
    (root / 'run.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    raise SystemExit(receipt['exitCode'])

before = digest(binary)
(root / 'binary.sha256').write_text(f'{before}  {binary}\n')
command = ['/usr/bin/caffeinate', '-i', binary, 's2', '--work-dir', str(work),
           '--output-dir', str(root / 'output'), '--load', '--real-expiry']
load_start = load()
started = now()
begin = time.monotonic()
with (root / 's2-output.txt').open('xb') as stream:
    outcome = run_owned(command, cwd=str(root), env=environment, stdout=stream, timeout=3600)
wall = time.monotonic() - begin
receipt.update({'commandArgv': command, 'runCwd': str(root), 'binarySHA256Before': before,
                'binarySHA256After': digest(binary), 'startedAt': started, 'endedAt': now(),
                'wallSeconds': wall, 'exitCode': outcome['wrapperStatus'],
                'loadAtStart': load_start, 'loadAtEnd': load(),
                'workDirectoryRemainsAfterRun': work.exists(),
                'gitStatusShortAtEnd': git('status', '--short'),
                'treeUnchangedByRun': git('status', '--short') == dirty,
                'treeCleanAtEnd': git('status', '--short') == '',
                'commitAtEnd': git('rev-parse', 'HEAD').strip(), **outcome})
(root / 'run.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
raise SystemExit(outcome['wrapperStatus'])
