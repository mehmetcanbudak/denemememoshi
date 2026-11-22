#!/usr/bin/env python3
"""Independently recompute every retained S2 load distribution/window/rate and reconcile relay totals.

Adapted copy of ../evidence/2026-11-03-memoshi-wave3-integration/verify_s2_samples.py (outside the
repository) for the report format of 2026-11-13. Every change is marked with a `2026-11-13`
comment; verify_s2_samples.diff in ../evidence/2026-11-13-memoshi-canonical-s2/ holds the full
difference. Since its move into scripts/ (2026-11-18), every check is a `require` call instead of
an `assert`, so `python3 -O` cannot skip one.
"""
import csv
import json
import math
from pathlib import Path
import sys
import traceback


def require(condition, detail=None):
    """One check: on failure, print the check and stop with exit status 1 before any result."""
    if not condition:
        caller = traceback.extract_stack(limit=2)[0]
        message = f'verify_s2_samples.py:{caller.lineno}: check failed: {caller.line}'
        raise SystemExit(message if detail is None else f'{message}: {detail!r}')


def distribution(samples):
    values = sorted(samples)
    if not values:
        return {'n': 0}
    result = {'n': len(values), 'minMs': values[0] / 1e6,
              'maxMs': values[-1] / 1e6, 'meanMs': sum(values) / len(values) / 1e6}
    for percentile in [50, 95, 99]:
        result[f'p{percentile}Ms'] = values[(percentile * len(values) + 99) // 100 - 1] / 1e6
    return result


def equal_distribution(actual, expected, label):
    require(set(actual) == set(expected), (label, actual, expected))
    for key, value in expected.items():
        require(math.isclose(actual[key], value, rel_tol=1e-12, abs_tol=1e-9), (label, key, actual[key], value))


def rows(path, fields):
    with path.open(newline='') as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == fields, (path, reader.fieldnames))
        return [{key: int(value) for key, value in row.items()} for row in reader]


def verify(root, destination):
    published = json.loads((root / 's2-measurements.json').read_text())
    # 2026-11-13: the report carries `passed` and `failures` instead of `findings`.
    require(published['passed'] is True, published['passed'])
    require(published['failures'] == [], published['failures'])
    require(len(published['loads']) == 4)
    result = {'verified': True, 'scope': 'load CSVs only; scenario CSVs are rounded milliseconds',
              'workersVerified': 0, 'rawCSVsVerified': 0, 'distributionsVerified': 0, 'profiles': {}}
    for profile, workers in sorted(published['loads'].items()):
        require(len(workers) == 3)
        merged = {'claims': [], 'renewals': [], 'moves': [], 'lateness': []}
        starts, ends = [], []
        initial_claims = 0
        steady_operations = 0
        periodic_leases = 0
        for index, report in enumerate(workers):
            directory = root / 'load-samples' / profile / str(index)
            retained = json.loads((directory / 'report.json').read_text())
            require(retained == report, (profile, index, 'report does not match matrix'))
            for key in ['errors', 'claimFailures', 'moveFailures', 'loadInducedExpiries', 'fencedRenewals', 'recoveryClaims']:
                require(report[key] == 0, (profile, index, key, report[key]))
            samples = {}
            for name in ['claims', 'renewals', 'moves']:
                samples[name] = [row['duration_ns'] for row in rows(directory / (name + '.csv'), ['duration_ns'])]
                require(all(value >= 0 for value in samples[name]))
                merged[name].extend(samples[name])
            scheduler = rows(directory / 'scheduler.csv', ['monotonic_ns', 'lateness_ns'])
            require(all(row['lateness_ns'] >= 0 for row in scheduler))
            start = report['steadyStartMonotonicNs']
            elapsed_ns = round(report['steadyPhaseSeconds'] * 1e9)
            options = report['options']
            requested_end = start + options['durationMs'] * 1_000_000
            window_ns = min(options['durationMs'] // 4, 10_000) * 1_000_000
            require(report['steadyPhaseSeconds'] >= options['durationMs'] / 1000)
            require(all(start <= row['monotonic_ns'] <= start + elapsed_ns for row in scheduler))
            require([row['monotonic_ns'] for row in scheduler] == sorted(row['monotonic_ns'] for row in scheduler))
            samples['lateness'] = [row['lateness_ns'] for row in scheduler]
            samples['latenessFirstWindow'] = [row['lateness_ns'] for row in scheduler if row['monotonic_ns'] < start + window_ns]
            samples['latenessLastWindow'] = [row['lateness_ns'] for row in scheduler if row['monotonic_ns'] >= requested_end - window_ns]
            merged['lateness'].extend(samples['lateness'])
            for name, values in samples.items():
                equal_distribution(report[name], distribution(values), f'{profile}/{index}/{name}')
                result['distributionsVerified'] += 1
            require(report['renewOperations'] == len(samples['renewals']) == len(scheduler))
            require(math.isclose(report['renewalsPerSecond'], len(samples['renewals']) / report['steadyPhaseSeconds'], rel_tol=1e-12))
            require(math.isclose(report['operationsPerSecond'], report['authorityOperations'] / report['steadyPhaseSeconds'], rel_tol=1e-12))
            starts.append(start)
            ends.append(start + elapsed_ns)
            initial_claims += len(samples['claims'])
            steady_operations += report['authorityOperations']
            periodic_leases += report['periodicallyRenewedLeases']
            result['workersVerified'] += 1
            result['rawCSVsVerified'] += 4
        relay = published['relays']['load-' + profile]
        counters = relay['counters']
        observed_rpc_total = relay['statistics']['authorityMessages']
        require(initial_claims + steady_operations == observed_rpc_total, (profile, 'RPC total mismatch'))
        require(sum(counters[key] for key in ['claimsGranted', 'claimsDenied', 'renewalsApplied', 'renewalsDenied', 'releases', 'releasesIgnored']) == observed_rpc_total)
        for key in ['renewalsDenied', 'releasesIgnored', 'groupCommitsDenied', 'revokedRefusals']:
            require(counters[key] == 0, (profile, key))
        require(counters['renewalsApplied'] == len(merged['renewals']))
        require(counters['claimsGranted'] == initial_claims + len(merged['moves']))
        require(counters['releases'] == (len(merged['moves']) if workers[0]['options']['idleRenewMs'] > 0 else 0))
        # lease.release is an unacknowledged send. A move may receive busy claim results until
        # that release reaches the authority; every such retry must still count as a real RPC.
        minimum_operations = len(merged['renewals']) + len(merged['moves']) + counters['releases']
        require(steady_operations == minimum_operations + counters['claimsDenied'])
        extent = (max(ends) - min(starts)) / 1e9
        result['profiles'][profile] = {
            'users': sum(worker['options']['users'] for worker in workers),
            'devices': sum(worker['devices'] for worker in workers),
            'conversations': sum(worker['conversations'] for worker in workers),
            'periodicallyRenewedLeases': periodic_leases,
            'steadyAuthorityOperations': steady_operations,
            'busyClaimRetries': counters['claimsDenied'],
            'observedRelayAuthorityMessagesIncludingInitialClaims': observed_rpc_total,
            'cohortExtentSeconds': extent,
            'cohortOperationsPerSecond': steady_operations / extent,
            'cohortRenewalsPerSecond': len(merged['renewals']) / extent,
            'pooled': {name: distribution(values) for name, values in merged.items()},
            'relayLifecycleCPUSeconds': relay['cpuSeconds'],
            'relayLifecycleMaximumResidentBytes': relay['maximumResidentBytes'],
        }
    # 2026-11-13: written beside the harness output, not into it.
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: verify_s2_samples.py S2_OUTPUT_DIRECTORY NEW_RESULT.json')
    verify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
