#!/usr/bin/env python3
"""One extra check for an S2 output directory, kept apart from check_d123_v2.py. Read-only.

usage: check_d133_extra.py S2_OUTPUT_DIRECTORY RESULT.json

Added 2026-11-14 for s2-full-04 (commit 4db72e2), at Main's request: s2-full-03 reported
`recovery.unacceptedOldEpochReported` 10; commit 4db72e2 fixes its cause, so it must now be 0.
The harness reports the counter and does not require it. Three checks:
- report: counters["recovery.unacceptedOldEpochReported"] == 0 (and absent or 0 in stress.counters);
- independent: logs/mac.stdout.jsonl and logs/phone.stdout.jsonl exist and each holds the device's
  `ready` event, so a missing or renamed log never recounts as 0;
- independent: no node event `applicationRecoveryRequired` with detail `unacceptedOldEpoch` in
  those two logs (the events the driver counts), and the same count over every device log, reported.
"""
import json
from pathlib import Path
import sys

out = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).resolve()
report = json.loads((out / 's2-measurements.json').read_text())
name = 'recovery.unacceptedOldEpochReported'
checks = []


def check(name_, source, measured, ok, expected):
    checks.append({'check': name_, 'source': source, 'expected': expected, 'measured': measured, 'ok': bool(ok)})


reported = report['counters'].get(name)
stress = ((report.get('stress') or {}).get('counters') or {}).get(name)
check(name, 'report: counters, stress.counters', {'counters': reported, 'stress.counters': stress},
      reported == 0 and stress in (None, 0), 'counters 0; stress absent or 0')


def recovery_events(path):
    """The log's applicationRecoveryRequired events by detail, and whether it holds a ready event."""
    found = {}
    ready = False
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        ready = ready or event.get('event') == 'ready'
        if event.get('event') == 'node' and event.get('kind') == 'applicationRecoveryRequired':
            detail = str(event.get('detail'))
            found[detail] = found.get(detail, 0) + 1
    return found, ready


scanned = {path.name: recovery_events(path) for path in sorted((out / 'logs').glob('*.stdout.jsonl'))
           if not path.name.startswith('load-') and not path.name.startswith('relay')}
by_log = {log: found for log, (found, ready) in scanned.items()}
counted_logs = [f'{device}.stdout.jsonl' for device in ('mac', 'phone')]
present = {log: log in scanned and scanned[log][1] for log in counted_logs}
check('the counted device logs exist and each holds a ready event',
      'independent: logs/mac.stdout.jsonl and logs/phone.stdout.jsonl', present, all(present.values()),
      'both present with a ready event')
counted = sum(by_log.get(log, {}).get('unacceptedOldEpoch', 0) for log in counted_logs)
check('applicationRecoveryRequired events with detail unacceptedOldEpoch',
      'independent: logs/mac.stdout.jsonl and logs/phone.stdout.jsonl (the logs the driver counts)',
      {'macAndPhone': counted, 'allDeviceLogsByDetail': by_log}, counted == 0, 0)

result = {'allChecksOk': all(item['ok'] for item in checks), 'checks': checks}
destination.write_text(json.dumps(result, indent=1, sort_keys=True) + '\n')
for item in checks:
    print(('ok   ' if item['ok'] else 'FAIL ') + item['check'] + ' | ' + json.dumps(item['measured'], sort_keys=True))
print('all checks ok' if result['allChecksOk'] else 'SOME CHECKS FAILED')
raise SystemExit(0 if result['allChecksOk'] else 1)
