#!/usr/bin/env python3
"""Check the points D123 names in one retained S2 output directory. Read-only.

usage: check_d123_v2.py S2_OUTPUT_DIRECTORY EXIT_STATUS RESULT.json

Version 2 (2026-11-14, for s2-full-03): a copy of check_d123.py for the report format of D133.
The report now has a qualified phase (8 devices; series and counters at the top level) and a
stress phase (the object `stress`, whose counters and series carry no prefix). Every check of
check_d123.py is kept; the two-writer audits and the expiry window are now checked in both
phases. Added: group sizes; every pairing of both phases succeeds; the three QR negative checks;
the revoked device holds a lease before its revocation; the authority's own refusal
(`revokedProbe` reply in logs/relay.stdout.jsonl); renewals, grants and writes of the revoked
device after its revocation; the successor; the revoked conversation's two-writer audit.
One earlier check is changed: the expiry conversation is matched by at least, not exactly, the
Mac's renewRefused count (see the comment there).
check_d123.py is unchanged; check_d123_v2.diff holds the difference. Both stay in the evidence
folder ../evidence/2026-11-13-memoshi-canonical-s2/, outside the repository.
Every check that compares a counter with 0 reads it through `required_counter`: an absent counter
is a failed check of its own, never 0.
2026-11-18 (HT-09): the scenarios that run once, after the stress phase (QR negative checks, real
QR expiry, revocation and its two-writer audit), report in the object `once`: every `qr.*`,
`revoke.*` and `audit.revoked.*` counter is read from `once.counters`, and the group they ran in
from `once.groupDevices` and counters["group.once.devices"]. The relay's refusal count must
cover the raw relay hello and both raw probes that met a closed connection, as the driver checks.

Inputs: s2-measurements.json (the report), main-relay-summary.json, main-relay-journal.bin and
logs/{mac,phone,ipad}.stdout.jsonl. Each check names its source. "report" checks read the
driver's own counters; "independent" checks recount from the relay's files and the device
processes' logs without the driver's counters.

Relay journal records are `kind(1) | length(u32 BE) | bytes`; kinds 1 send, 2 authority,
3 authorityReply, 4 control, 5 controlReply. Kinds 2 and 3 are DeviceMessage JSON
(type, payload, sentAt, from, to). Device logs are JSON lines: node events
({"event":"node","kind":…,"at":monotonic ns,…}) and command replies ({"op":…,"id":…,"ok":…}).
"""
import base64
import collections
import json
from pathlib import Path
import struct
import sys

out = Path(sys.argv[1]).resolve()
exit_status = int(sys.argv[2])
destination = Path(sys.argv[3]).resolve()
report = json.loads((out / 's2-measurements.json').read_text())
counters = report['counters']
stress_counters = (report.get('stress') or {}).get('counters') or {}
stress_series = (report.get('stress') or {}).get('series') or {}
phases = {'qualified': (counters, report['series']), 'stress': (stress_counters, stress_series)}
once = report.get('once') or {}
once_counters = once.get('counters') or {}
sections = {'qualified': counters, 'stress': stress_counters, 'once': once_counters}
section_sources = {'qualified': 'report: counters', 'stress': 'report: stress.counters', 'once': 'report: once.counters'}
checks = []
facts = {}


def check(point, name, source, measured, ok, expected):
    checks.append({'point': point, 'check': name, 'source': source, 'expected': expected,
                   'measured': measured, 'ok': bool(ok)})


def once_counter(name):
    return once_counters.get(name, 0)


def phase_counter(phase, name):
    return phases[phase][0].get(name, 0)


missing_required = set()


def required_counter(name, section='qualified'):
    """A counter that a check compares with 0, from report section `section` (qualified, stress
    or once). An absent counter is recorded as a failed check (once) and reads as None, so no
    comparison with 0 passes on a counter the run did not report."""
    source = sections[section]
    if name in source:
        return source[name]
    if (section, name) not in missing_required:
        missing_required.add((section, name))
        check('required counters', 'required counter present', section_sources[section],
              {'section': section, 'counter': name}, False, 'present')
    return None


def lines(device):
    result = []
    for line in (out / 'logs' / f'{device}.stdout.jsonl').read_text().splitlines():
        try:
            result.append(json.loads(line))
        except ValueError:
            result.append({'unparsed': line})
    return result


logs = {device: lines(device) for device in ('mac', 'phone', 'ipad')}
unparsed = {device: sum(1 for line in logs[device] if 'unparsed' in line) for device in logs}
ids = {device: next(line['deviceId'] for line in logs[device] if line.get('event') == 'ready')
       for device in logs}
facts['deviceIds'] = ids
facts['unparsedLogLines'] = unparsed


def events(device, kind):
    return [line for line in logs[device] if line.get('event') == 'node' and line.get('kind') == kind]


# --- a. the report's own verdict ---------------------------------------------------------
check('verdict', 'process exit status', 'argument (run.json exitCode)', exit_status, exit_status == 0, 0)
check('verdict', 'passed', 'report: passed', report.get('passed'), report.get('passed') is True, True)
check('verdict', 'failures', 'report: failures', report.get('failures'), report.get('failures') == [], [])
check('verdict', 'full counts selected', 'report: quick', report.get('quick'), report.get('quick') is False, False)
check('verdict', 'real QR expiry selected', 'report: realQRExpirySelected',
      report.get('realQRExpirySelected'), report.get('realQRExpirySelected') is True, True)
check('verdict', 'authority load selected', 'report: authorityLoadSelected',
      report.get('authorityLoadSelected'), report.get('authorityLoadSelected') is True, True)
facts['notes'] = report.get('notes')
facts['evidenceClass'] = report.get('evidenceClass')
facts['storage'] = report.get('storage')
facts['host'] = report.get('host')

# --- relay journal and summary -------------------------------------------------------------
summary = json.loads((out / 'main-relay-summary.json').read_text())
check('relays', 'retained main summary equals the report', 'main-relay-summary.json vs report: relays.main',
      summary == report['relays']['main'], summary == report['relays']['main'], True)
# The journal is read record by record; only authority records (kinds 2 and 3) are decoded and
# kept, so a journal of several hundred MB does not have to fit in memory twice.
records = []
kinds = collections.Counter()
types = collections.Counter()
payload_bytes = 0
bytes_by_kind = collections.Counter()
truncated = False
with (out / 'main-relay-journal.bin').open('rb') as stream:
    while True:
        header = stream.read(5)
        if not header:
            break
        if len(header) != 5:
            truncated = True
            break
        kind = header[0]
        length = struct.unpack('>I', header[1:5])[0]
        body = stream.read(length)
        if len(body) != length:
            truncated = True
            break
        kinds[kind] += 1
        payload_bytes += length
        bytes_by_kind[kind] += length
        message = None
        if kind in (2, 3):
            try:
                message = json.loads(body)
                types[(kind, message.get('type'))] += 1
            except ValueError:
                types[(kind, '<not JSON>')] += 1
        records.append((kind, message, None))
facts['journalRecordKinds'] = {str(kind): count for kind, count in sorted(kinds.items())}
facts['journalAuthorityTypes'] = {f'{kind}:{name}': count for (kind, name), count in sorted(types.items(), key=str)}
check('relays', 'journal record kinds', 'independent: main-relay-journal.bin', sorted(kinds),
      not truncated and set(kinds) <= {1, 2, 3, 4, 5}, 'subset of 1-5, no truncated record')
closed = (summary.get('journal') or {}).get('closed', {}).get('counts')
check('relays', 'journal entries and payload bytes equal the summary', 'independent: journal vs relays.main.journal.closed.counts',
      {'parsed': {'entries': len(records), 'bytes': payload_bytes}, 'summary': closed},
      closed == {'entries': len(records), 'bytes': payload_bytes} or closed == {'bytes': payload_bytes, 'entries': len(records)},
      'equal')
# Only the main relay keeps a grant log. The load relays run with `--no-grant-log`, so they report
# no grant count and no duplicate count at all: a 0 there would be vacuous.
relay_state = {name: {'duplicateGrants': relay.get('duplicateGrants'), 'journalClosed': 'closed' in (relay.get('journal') or {})}
               for name, relay in sorted(report['relays'].items())}
check('relays', 'duplicateGrants 0 on the main relay, not measured on the load relays, every journal closed', 'report: relays.*',
      relay_state,
      len(relay_state) == 5 and relay_state.get('main', {}).get('duplicateGrants') == 0
      and all(state['duplicateGrants'] is None for name, state in relay_state.items() if name != 'main')
      and all(state['journalClosed'] for state in relay_state.values()),
      '5 relays: main 0, load relays none, all closed')

# --- pairing and group size (added after s2-full-01, whose failure was in pairing) --------------
probe_replies = [line for line in logs['phone'] if line.get('op') == 'pairProbe']
probe_outcomes = collections.Counter(
    'paired' if line.get('paired') is True else 'refused: ' + str(line.get('refusal')) for line in probe_replies)
mac_paired = events('mac', 'paired')
mac_refused = collections.Counter(event.get('detail') for event in events('mac', 'refused'))
roster_sizes = []
for kind, message, body in records:
    if kind == 2 and message and message.get('type') == 'group.commit':
        payload = message.get('payload') or {}
        try:
            commit = json.loads(base64.b64decode(payload.get('commit') or ''))
            roster_sizes.append((payload.get('change'), len(commit.get('members') or [])))
        except ValueError:
            roster_sizes.append((payload.get('change'), None))
sizes = [size for change, size in roster_sizes if size is not None]
facts['pairing'] = {
    'phonePairProbeReplies': len(probe_replies), 'phonePairProbeOutcomes': dict(probe_outcomes),
    'macPairedEvents': len(mac_paired), 'macRefusedEventsByDetail': dict(mac_refused),
    'groupCommitsInJournal': len(roster_sizes),
    'groupCommitsByChange': dict(collections.Counter(change for change, size in roster_sizes)),
    'largestRosterInAGroupCommit': max(sizes) if sizes else None,
    'rosterInLastGroupCommit': roster_sizes[-1] if roster_sizes else None,
    'seriesPairingProbeTotalN': (report['series'].get('pairing.probe.total') or {}).get('n'),
    'sources': 'logs/phone.stdout.jsonl pairProbe replies; logs/mac.stdout.jsonl paired and refused events; '
               'main-relay-journal.bin group.commit records (members of the decoded commit)'}
check('pairing', 'pairing.unexpectedRefusal and qr.afterWrongKey.refused', 'report: counters, once.counters',
      {'pairing.unexpectedRefusal': required_counter('pairing.unexpectedRefusal'), 'qr.afterWrongKey.refused': required_counter('qr.afterWrongKey.refused', 'once'),
       'qr.afterWrongKey.paired': once_counter('qr.afterWrongKey.paired')},
      required_counter('pairing.unexpectedRefusal') == 0 and required_counter('qr.afterWrongKey.refused', 'once') == 0, 'both 0')
check('pairing', 'probes paired and largest group', 'independent: device logs and relay journal',
      {'probesPaired': probe_outcomes.get('paired', 0), 'macPairedEvents': len(mac_paired),
       'largestRosterInAGroupCommit': max(sizes) if sizes else None,
       'macRefusedMessageTooLarge': mac_refused.get('messageTooLarge', 0), 'macRefusedGroupFull': mac_refused.get('groupFull', 0)},
      probe_outcomes.get('paired', 0) == 51 and len(mac_paired) == 53 and (max(sizes) if sizes else 0) == 54
      and mac_refused.get('messageTooLarge', 0) == 0 and mac_refused.get('groupFull', 0) == 0,
      '51 probes paired (50 samples and the right key after a wrong key); 53 paired events on the Mac; 54 members; no messageTooLarge or groupFull refusal')
facts['scenarioFigures'] = {
    'handover.rebalance': report['series'].get('handover.rebalance'),
    'writes.accepted': counters.get('writes.accepted'), 'writes.refused': counters.get('writes.refused'),
    'mainRelayJournalFileBytes': (out / 'main-relay-journal.bin').stat().st_size,
    'mainRelayJournalPayloadBytesByKind': {str(kind): size for kind, size in sorted(bytes_by_kind.items())}}

# --- revocation ---------------------------------------------------------------------------------
ipad, mac = ids['ipad'], ids['mac']
removal = None
for index, (kind, message, body) in enumerate(records):
    if kind == 2 and message and message.get('type') == 'group.commit' and (message.get('payload') or {}).get('change') == 'remove':
        removal = index
removal_reply = None
if removal is not None:
    for index in range(removal + 1, len(records)):
        kind, message, body = records[index]
        if kind == 3 and message and message.get('type') == 'group.commitResult':
            removal_reply = index
            break
revoked_at = None
if removal_reply is not None:
    reply = records[removal_reply][1]
    revoked_at = reply.get('sentAt')
    facts['revocation'] = {
        'removalRequestFrom': (records[removal][1].get('from') or {}).get('deviceId'),
        'removalsInJournal': sum(1 for kind, message, body in records if kind == 2 and message and message.get('type') == 'group.commit' and (message.get('payload') or {}).get('change') == 'remove'),
        'authorityReply': reply.get('payload'), 'authorityReplySentAtWallMs': revoked_at,
        'source': 'main-relay-journal.bin: last group.commit with change=remove and the group.commitResult after it'}
check('revocation', 'the authority accepted the removal', 'independent: main-relay-journal.bin',
      facts.get('revocation'),
      revoked_at is not None and records[removal_reply][1]['payload'].get('accepted') is True
      and records[removal_reply][1]['payload'].get('epoch') == once_counter('revoke.groupEpoch'),
      'accepted, epoch equal to once.counters["revoke.groupEpoch"]')

# relay level
check('revocation: relay level', 'revoke.relay.refused', 'report: once.counters', once_counter('revoke.relay.refused'),
      once_counter('revoke.relay.refused') >= 1, '>= 1')
check('revocation: relay level', 'revoke.relay.accepted', 'report: once.counters', required_counter('revoke.relay.accepted', 'once'),
      required_counter('revoke.relay.accepted', 'once') == 0, 0)
# Each probe the driver counts as refused by the relay (the raw hello, and a raw claim or renewal
# that met a closed connection) raised the relay's own refusal count by one.
refusals = summary['statistics'].get('refusals')
relay_refused = (once_counter('revoke.relay.refused') + once_counter('revoke.claim.connectionClosed')
                 + once_counter('revoke.renew.connectionClosed'))
check('revocation: relay level', "the relay's own refusal count", 'independent: main-relay-summary.json statistics.refusals',
      {'refusals': refusals, 'relayRefusedProbes': relay_refused},
      refusals is not None and refusals >= max(1, relay_refused),
      '>= revoke.relay.refused + revoke.claim.connectionClosed + revoke.renew.connectionClosed, and >= 1')
facts['relayMainCounters'] = summary.get('counters')
facts['relayMainStatistics'] = summary.get('statistics')
raw = {op: [line for line in logs['ipad'] if line.get('op') == op] for op in ('rawRelayHello', 'rawClaim', 'rawLink')}
facts['revokedDeviceRawProbeReplies'] = raw
check('revocation: relay level', 'raw relay hello by the revoked device', 'independent: logs/ipad.stdout.jsonl reply to rawRelayHello',
      raw['rawRelayHello'], len(raw['rawRelayHello']) >= 1 and all(line.get('ok') is True and line.get('accepted') is False for line in raw['rawRelayHello']),
      'accepted false')

# claim level
check('revocation: claim level', 'revoke.claim.refused', 'report: once.counters', once_counter('revoke.claim.refused'),
      once_counter('revoke.claim.refused') >= 1, '>= 1')
check('revocation: claim level', 'revoke.claim.accepted', 'report: once.counters', required_counter('revoke.claim.accepted', 'once'),
      required_counter('revoke.claim.accepted', 'once') == 0, 0)
# Which refusal the raw claim and renewal met is reported, not checked: either value passes, so it
# is a fact. 1 = the relay held no connection for the revoked device, 0 = the authority denied it.
facts['revokeClaimConnectionClosed'] = {
    'value': once_counters.get('revoke.claim.connectionClosed'), 'source': 'report: once.counters revoke.claim.connectionClosed',
    'meaning': '1 = the relay held no connection for the revoked device, 0 = the authority denied the claim'}
facts['revokeRenewConnectionClosed'] = {
    'value': once_counters.get('revoke.renew.connectionClosed'), 'source': 'report: once.counters revoke.renew.connectionClosed',
    'meaning': '1 = the relay held no connection for the revoked device, 0 = the authority denied the renewal'}
check('revocation: claim level', 'raw claim by the revoked device', 'independent: logs/ipad.stdout.jsonl reply to rawClaim',
      raw['rawClaim'], len(raw['rawClaim']) >= 1 and all(line.get('ok') is True and line.get('granted') is not True
                                                         and line.get('answered') in (True, False) for line in raw['rawClaim']),
      'answered false, or answered true with granted false')
grants = summary['grantLog']
to_revoked = [grant for grant in grants if grant['runner'] == ipad]
late = [grant for grant in to_revoked if revoked_at is not None and grant['grantedAt'] >= revoked_at]
check('revocation: claim level', 'grants to the revoked device from the revocation on',
      'independent: main-relay-summary.json grantLog, revocation time from the journal',
      {'grantLogEntries': len(grants), 'toRevokedDeviceWholeRun': len(to_revoked), 'toRevokedDeviceFromRevocationOn': len(late)},
      revoked_at is not None and len(late) == 0, '0 from the revocation on')
after = records[removal_reply + 1:] if removal_reply is not None else []
from_revoked = collections.Counter(message.get('type') for kind, message, body in after
                                   if kind == 2 and message and (message.get('from') or {}).get('deviceId') == ipad)
granted_after = [message for kind, message, body in after
                 if kind == 3 and message and (message.get('to') or {}).get('deviceId') == ipad
                 and (message.get('payload') or {}).get('granted') is True]
check('revocation: claim level', 'authority records from or granting to the revoked device after the removal',
      'independent: main-relay-journal.bin',
      {'requestsFromRevokedDeviceByType': dict(from_revoked), 'grantsToRevokedDevice': len(granted_after),
       'recordsAfterRemoval': len(after)},
      removal_reply is not None and len(granted_after) == 0, '0 grants')

# link level
check('revocation: link level', 'revoke.link.refused', 'report: once.counters', once_counter('revoke.link.refused'),
      once_counter('revoke.link.refused') >= 1, '>= 1')
check('revocation: link level', 'revoke.link.accepted', 'report: once.counters', required_counter('revoke.link.accepted', 'once'),
      required_counter('revoke.link.accepted', 'once') == 0, 0)
check('revocation: link level', 'raw link by the revoked device', 'independent: logs/ipad.stdout.jsonl reply to rawLink',
      raw['rawLink'], len(raw['rawLink']) >= 1 and all(line.get('ok') is True and line.get('linked') is False for line in raw['rawLink']),
      'linked false')
revoked_events = [event for event in events('mac', 'revoked') if event.get('peer') == ipad]
mac_revoked_at = revoked_events[-1]['at'] if revoked_events else None
refused_after = [event for event in events('mac', 'refused')
                 if mac_revoked_at is not None and event['at'] > mac_revoked_at
                 and event.get('route') == 'direct' and event.get('peer') is None]
links_after = [event for event in events('mac', 'linkUp')
               if mac_revoked_at is not None and event['at'] > mac_revoked_at and event.get('peer') == ipad]
check('revocation: link level', "the peer's own handshake refusals after it applied the revocation",
      'independent: logs/mac.stdout.jsonl, `refused` events on route direct naming no peer, after the `revoked` event',
      {'macRevokedEvents': len(revoked_events), 'refusedAfterByDetail': dict(collections.Counter(event.get('detail') for event in refused_after))},
      sum(1 for event in refused_after if event.get('detail') == 'unknownPeer') >= 1, '>= 1 with detail unknownPeer')
check('revocation: link level', 'links to the revoked device that came up after the revocation',
      'independent: logs/mac.stdout.jsonl, `linkUp` events naming the revoked device after the `revoked` event',
      len(links_after), mac_revoked_at is not None and len(links_after) == 0, 0)

# --- two-writer audits ----------------------------------------------------------------------------
def audit(conversation):
    commits = sorted(((event, device) for device in ('mac', 'phone') for event in events(device, 'committed')
                      if event.get('conversation') == conversation), key=lambda pair: pair[0]['at'])
    writer = {}
    devices = set()
    highest = 0
    result = {'commits': len(commits), 'commitsWithoutEpoch': 0, 'epochWentBackwards': 0, 'twoWriterEpochs': 0}
    for event, device in commits:
        epoch = event.get('epoch')
        if epoch is None:
            result['commitsWithoutEpoch'] += 1
            continue
        if epoch < highest:
            result['epochWentBackwards'] += 1
        highest = max(highest, epoch)
        if epoch in writer and writer[epoch] != device:
            result['twoWriterEpochs'] += 1
        writer[epoch] = device
        devices.add(device)
    result['epochs'] = len(writer)
    result['writers'] = len(devices)
    result['commitsByDevice'] = dict(collections.Counter(device for event, device in commits))
    result['epochsByDevice'] = dict(collections.Counter(writer.values()))
    return result


conversations = {event.get('conversation') for device in ('mac', 'phone') for event in events(device, 'committed')}
audits = {conversation: audit(conversation) for conversation in conversations if conversation}
renew_refused = collections.Counter(event.get('conversation') for event in events('mac', 'renewRefused'))
facts['conversationsWithCommits'] = len(audits)
fields = ('commits', 'epochs', 'writers', 'commitsWithoutEpoch', 'epochWentBackwards', 'twoWriterEpochs')
for phase, label in [(phase, label) for phase in phases for label in ('chat', 'session', 'expiry')]:
    phase_counters = phases[phase][0]
    point = f'two-writer audit: {label}' if phase == 'qualified' else f'stress phase, two-writer audit: {label}'
    reported = {field: phase_counters.get(f'audit.{label}.{field}') for field in fields}
    required = {'writers': phase_counters.get(f'audit.{label}.requiredWriters'), 'epochs': phase_counters.get(f'audit.{label}.requiredEpochs')}
    ok = (reported['commits'] or 0) > 0 and reported['commitsWithoutEpoch'] == 0 and reported['epochWentBackwards'] == 0 \
        and reported['twoWriterEpochs'] == 0
    floor = 1 if label == 'session' else 2
    ok = ok and (reported['writers'] or 0) >= floor and (reported['epochs'] or 0) >= floor
    check(point, f'audit.{label}.* counters', 'report: counters' if phase == 'qualified' else 'report: stress.counters',
          {'reported': reported, 'requiredByHarness': required, 'replicaRejections': phase_counters.get(f'audit.{label}.replicaRejections')},
          ok, f'commits > 0, writers >= {floor}, epochs >= {floor}, the three fault counters 0')
    # The report does not name the conversation. It is the one whose recount equals the reported
    # counters; for expiry it must also carry the Mac's renewRefused events. v2: at least as many as
    # the counter, not exactly as many: the driver reads the counter once, before the audit, and a
    # refusal logged after that read is still in the log (seen in a quick run of 2026-11-13).
    candidates = [conversation for conversation, recount in audits.items()
                  if all(recount[field] == reported[field] for field in fields)
                  and (label != 'expiry' or renew_refused.get(conversation, 0) >= max(1, phase_counter(phase, 'expiry.renewRefusedOnMac')))]
    recount = audits[candidates[0]] if len(candidates) == 1 else None
    check(point, 'recount of the committed events of the Mac and the iPhone',
          'independent: logs/mac.stdout.jsonl and logs/phone.stdout.jsonl, `committed` events of the one conversation whose recount equals the counters',
          {'conversation': candidates[0] if len(candidates) == 1 else None, 'matchingConversations': len(candidates), 'recount': recount},
          len(candidates) == 1, 'exactly one conversation reproduces the reported counters')

# expiry window, both phases
for phase in phases:
    must_be_zero = ('expiry.oldRunner.concurrentAccepted', 'expiry.staleAccepted')
    expiry = {name: required_counter(name, phase) if name in must_be_zero else phase_counter(phase, name) for name in (
        'expiry.beforeFreeze.accepted', 'expiry.oldRunner.concurrentAccepted', 'expiry.oldRunner.concurrentRefused',
        'expiry.successor.concurrentAccepted', 'expiry.staleRefused', 'expiry.staleAccepted', 'expiry.renewRefusedOnMac')}
    take_over = (phases[phase][1].get('expiry.takeOverAfterFreeze') or {})
    expiry['series.expiry.takeOverAfterFreeze'] = take_over
    check('expiry window' if phase == 'qualified' else 'stress phase, expiry window', 'frozen-runner take-overs',
          'report: counters and series' if phase == 'qualified' else 'report: stress.counters and stress.series', expiry,
          expiry['expiry.beforeFreeze.accepted'] == 20 and expiry['expiry.oldRunner.concurrentAccepted'] == 0
          and expiry['expiry.oldRunner.concurrentRefused'] > 0 and expiry['expiry.successor.concurrentAccepted'] > 0
          and expiry['expiry.staleRefused'] == 20 and expiry['expiry.staleAccepted'] == 0 and take_over.get('n') == 20,
          '20 cycles; old runner accepted 0 and refused > 0; successor accepted > 0; 20 stale writes refused, 0 accepted')
check('real QR expiry', 'qr.expired.refused / qr.expired.accepted', 'report: once.counters',
      {'refused': once_counter('qr.expired.refused'), 'accepted': required_counter('qr.expired.accepted', 'once')},
      once_counter('qr.expired.refused') == 1 and required_counter('qr.expired.accepted', 'once') == 0, 'refused 1, accepted 0')
facts['reportedNotRequired'] = {name: counters.get(name) for name in ('reservation.released', 'recovery.unacceptedOldEpochReported')}
facts['allRevokeCounters'] = {name: value for name, value in sorted(once_counters.items()) if name.startswith('revoke.')}
facts['allAuditAndExpiryCounters'] = {name: value for name, value in sorted(counters.items()) if name.startswith(('audit.', 'expiry.'))}

# --- added in v2 (D133): group sizes, pairings in both phases, QR negative checks ----------------
check('group size', 'qualified, stress and once-only group sizes',
      'report: counters group.*, qualified.groupDevices, stress.groupDevices, once.groupDevices',
      {'group.qualified.devices': counters.get('group.qualified.devices'), 'group.stress.devices': counters.get('group.stress.devices'),
       'group.once.devices': counters.get('group.once.devices'),
       'qualified.groupDevices': (report.get('qualified') or {}).get('groupDevices'),
       'stress.groupDevices': (report.get('stress') or {}).get('groupDevices'), 'once.groupDevices': once.get('groupDevices')},
      counters.get('group.qualified.devices') == 8 and counters.get('group.stress.devices') == 54
      and (report.get('qualified') or {}).get('groupDevices') == 8 and (report.get('stress') or {}).get('groupDevices') == 54
      and counters.get('group.once.devices') == 54 and once.get('groupDevices') == 54,
      'qualified 8, stress 54, once-only scenarios 54')
probe_series = {phase: (phases[phase][1].get('pairing.probe.total') or {}).get('n') for phase in phases}
check('pairing, both phases', 'no unexpected refusal; probe pairings per phase', 'report: counters, stress.counters, series pairing.probe.total',
      {'qualified.pairing.unexpectedRefusal': required_counter('pairing.unexpectedRefusal', 'qualified'),
       'stress.pairing.unexpectedRefusal': required_counter('pairing.unexpectedRefusal', 'stress'),
       'qualified.pairing.probe.total.n': probe_series['qualified'], 'stress.pairing.probe.total.n': probe_series['stress'],
       'pairing.device.total.n': (report['series'].get('pairing.device.total') or {}).get('n')},
      required_counter('pairing.unexpectedRefusal', 'qualified') == 0 and required_counter('pairing.unexpectedRefusal', 'stress') == 0
      and probe_series['qualified'] == 5 and probe_series['stress'] == 45
      and (report['series'].get('pairing.device.total') or {}).get('n') == 2,
      'both 0; 5 probes paired in the qualified phase, 45 in the stress phase; iPhone and iPad paired')
sequence = ['paired' if line.get('paired') is True else 'refused' for line in probe_replies]
expected_sequence = ['paired'] * 50 + ['refused', 'refused', 'refused', 'paired', 'refused']
check('pairing, both phases', 'order of the pairing probes', 'independent: logs/phone.stdout.jsonl pairProbe replies in order',
      {'replies': len(probe_replies), 'firstFiftyPaired': sequence[:50].count('paired'),
       'last5': [{'paired': line.get('paired'), 'refusal': line.get('refusal')} for line in probe_replies[50:]],
       'refusalsAmongFirstFifty': [line.get('refusal') for line in probe_replies[:50] if line.get('paired') is not True]},
      sequence == expected_sequence,
      '50 paired (5 qualified + 45 stress), then replay, voided and wrong-key refused, right key paired, expired code refused')
member_sizes = [size for change, size in roster_sizes if change != 'remove' and size is not None]
check('pairing, both phases', 'group grew one device per pairing and the authority refused no group change',
      'independent: main-relay-journal.bin group.commit rosters; main-relay-summary.json counters',
      {'rostersOfAdds': member_sizes[:10] + (['...'] if len(member_sizes) > 10 else []) + member_sizes[-3:],
       'groupCommitsApplied': summary['counters'].get('groupCommitsApplied'), 'groupCommitsDenied': summary['counters'].get('groupCommitsDenied')},
      member_sizes == list(range(2, 55)) and summary['counters'].get('groupCommitsDenied') == 0,
      'rosters 2..54 in order (8 reached before the stress phase); groupCommitsDenied 0')
qr = {name: required_counter(name, 'once') if name.endswith('.accepted') or name == 'qr.afterWrongKey.refused' else once_counter(name)
      for name in ('qr.replay.refused', 'qr.replay.accepted', 'qr.void.refused', 'qr.void.accepted',
                   'qr.wrongKey.refused', 'qr.wrongKey.accepted', 'qr.afterWrongKey.paired', 'qr.afterWrongKey.refused')}
check('QR negative checks', 'replayed, voided and wrong-key codes refused; the right key then pairs', 'report: once.counters', qr,
      qr['qr.replay.refused'] == 1 and qr['qr.void.refused'] == 1 and qr['qr.wrongKey.refused'] == 1
      and qr['qr.replay.accepted'] == 0 and qr['qr.void.accepted'] == 0 and qr['qr.wrongKey.accepted'] == 0
      and qr['qr.afterWrongKey.paired'] == 1 and qr['qr.afterWrongKey.refused'] == 0,
      'each refused 1 and accepted 0; afterWrongKey paired 1')
check('QR negative checks', "the Mac's own refusals", 'independent: logs/mac.stdout.jsonl `refused` events by detail',
      dict(mac_refused), mac_refused.get('alreadyUsed', 0) >= 1 and mac_refused.get('voided', 0) >= 1 and mac_refused.get('expired', 0) >= 1,
      'alreadyUsed (replay), voided and expired each >= 1; the wrong key is reported as it shows')

# --- added in v2 (D133): the revoked device held a lease; nothing for it afterwards ---------------
held_conversations = sorted({grant['conversationID'] for grant in to_revoked})
held = held_conversations[-1] if len(held_conversations) == 1 else None
held_epoch = max((grant['epoch'] for grant in to_revoked if grant['conversationID'] == held), default=None)
facts['revokedConversation'] = {'conversation': held, 'heldEpoch': held_epoch, 'conversationsGrantedToRevokedDevice': held_conversations,
                                'source': 'main-relay-summary.json grantLog, grants whose runner is the iPad'}
before_grants = [grant for grant in to_revoked if revoked_at is not None and grant['grantedAt'] < revoked_at]


def renewal_sent(event):
    fields = dict(part.split('=', 1) for part in (event.get('detail') or '').split() if '=' in part)
    try:
        return int(fields['expires_at']) - int(fields['ttl_ms'])
    except (KeyError, ValueError):
        return None


ipad_commits = [event for event in events('ipad', 'committed')]
ipad_renewals = [event for event in events('ipad', 'renewed') if event.get('conversation') == held]
renew_times = [renewal_sent(event) for event in ipad_renewals]
check('revocation: lease held before', 'revoke.lease.held, revoke.renewals.beforeRevocation', 'report: once.counters',
      {'revoke.lease.held': once_counter('revoke.lease.held'), 'revoke.renewals.beforeRevocation': once_counter('revoke.renewals.beforeRevocation'),
       'revoke.lease.expiredAtRemoval': once_counters.get('revoke.lease.expiredAtRemoval')},
      once_counter('revoke.lease.held') == 1 and once_counter('revoke.renewals.beforeRevocation') >= 1, 'held 1; renewals before >= 1')
check('revocation: lease held before', 'grant, commits and renewal of the revoked device before its revocation',
      'independent: main-relay-summary.json grantLog; logs/ipad.stdout.jsonl `committed` and `renewed` events; revocation time from the journal',
      {'conversation': held, 'heldEpoch': held_epoch, 'grantsBeforeRevocation': len(before_grants),
       'commitsBeforeMacRevokedEvent': sum(1 for event in ipad_commits if event.get('conversation') == held and mac_revoked_at is not None and event['at'] < mac_revoked_at),
       'renewalsSentBeforeRemoval': sum(1 for sent in renew_times if sent is not None and revoked_at is not None and sent < revoked_at),
       'renewalEventsWithoutExpiry': sum(1 for sent in renew_times if sent is None)},
      held is not None and len(before_grants) >= 1
      and sum(1 for event in ipad_commits if event.get('conversation') == held and mac_revoked_at is not None and event['at'] < mac_revoked_at) >= 3
      and sum(1 for sent in renew_times if sent is not None and revoked_at is not None and sent < revoked_at) >= 1,
      'one conversation granted to it before the revocation; >= 3 commits and >= 1 accepted renewal before it')

# the authority's own refusal
relay_lines = []
for line in (out / 'logs' / 'relay.stdout.jsonl').read_text().splitlines():
    try:
        relay_lines.append(json.loads(line))
    except ValueError:
        relay_lines.append({'unparsed': line})
probe = [line for line in relay_lines if line.get('op') == 'revokedProbe']
facts['authorityProbeReplies'] = probe
check('revocation: authority level', 'revoke.authority.refused / revoke.authority.accepted', 'report: once.counters',
      {'refused': once_counter('revoke.authority.refused'), 'accepted': required_counter('revoke.authority.accepted', 'once')},
      once_counter('revoke.authority.refused') == 1 and required_counter('revoke.authority.accepted', 'once') == 0, 'refused 1, accepted 0')
reply = probe[0] if len(probe) == 1 else {}
check('revocation: authority level', "the authority's own answer to the revoked device's claim and renewal",
      'independent: logs/relay.stdout.jsonl reply to revokedProbe; held conversation and epoch from the grant log',
      reply,
      len(probe) == 1 and reply.get('ok') is True and reply.get('isRevoked') is True and reply.get('revokedRefusals') == 2
      and reply.get('claimAnswered') is False and reply.get('claimGranted') is False
      and reply.get('renewAnswered') is False and reply.get('renewed') is False
      and reply.get('leaseUnchanged') is True and reply.get('leaseEpoch') == held_epoch + 1 and reply.get('leaseRunner') is None
      and reply.get('memberClaimGranted') is True,
      'one reply: isRevoked, 2 refusals counted by the authority, neither answered nor granted, lease record unchanged by the probe at the epoch the removal moved it to (held epoch + 1, no runner; protocol.md 12.5, 662ce10), a member claim granted on the same path')
check('revocation: authority level', "the authority's revoked-sender refusals in the relay summary",
      'independent: main-relay-summary.json counters.revokedRefusals', summary['counters'].get('revokedRefusals'),
      (summary['counters'].get('revokedRefusals') or 0) >= 2, '>= 2')
check('revocation: authority level', "a member's raw claim on the same path is granted and released",
      'report: once.counters revoke.control.rawClaimGranted', once_counter('revoke.control.rawClaimGranted'),
      once_counter('revoke.control.rawClaimGranted') == 1, 1)

# renewals
raw_renew = [line for line in logs['ipad'] if line.get('op') == 'rawRenew']
check('revocation: renewal', 'revoke.renew.refused / revoke.renew.accepted', 'report: once.counters',
      {'refused': once_counter('revoke.renew.refused'), 'accepted': required_counter('revoke.renew.accepted', 'once')},
      once_counter('revoke.renew.refused') >= 1 and required_counter('revoke.renew.accepted', 'once') == 0, 'refused >= 1, accepted 0')
renewed_after = [sent for sent in renew_times if sent is None or revoked_at is None or sent >= revoked_at]
check('revocation: renewal', 'raw renewal and accepted renewals after the removal',
      'independent: logs/ipad.stdout.jsonl rawRenew reply and `renewed` events (sent time = expires_at - ttl_ms) vs the journal removal time',
      {'rawRenew': raw_renew, 'renewedEventsOnHeldConversation': len(ipad_renewals), 'acceptedRenewalsSentFromRemovalOn': len(renewed_after)},
      len(raw_renew) >= 1 and all(line.get('ok') is True and line.get('renewed') is not True for line in raw_renew) and len(renewed_after) == 0,
      'not renewed; 0 accepted renewals sent from the removal on')

# writes and grants after revocation
commit_streams = [line for line in logs['ipad'] if line.get('op') == 'commitStream']
late_commits = [event for event in ipad_commits if mac_revoked_at is None or event['at'] >= mac_revoked_at]
write_refusals = {name: once_counters.get(name) for name in (
    'revoke.write.refused', 'revoke.write.refusedByFence', 'revoke.write.refusedByMembership')}
check('revocation: writes after', 'revoke.write.*', 'report: once.counters',
      {'accepted': required_counter('revoke.write.accepted', 'once'), 'refused': once_counter('revoke.write.refused'),
       'afterRevocation': required_counter('revoke.write.afterRevocation', 'once'), 'refusals': write_refusals},
      required_counter('revoke.write.accepted', 'once') == 0 and required_counter('revoke.write.afterRevocation', 'once') == 0
      and once_counter('revoke.write.refused') >= 1 and None not in write_refusals.values()
      and write_refusals['revoke.write.refused'] == write_refusals['revoke.write.refusedByFence'] + write_refusals['revoke.write.refusedByMembership'],
      'accepted 0, afterRevocation 0, refused >= 1 and equal to refusedByFence + refusedByMembership')


def stream_refusals(line):
    """refused, and fence plus membership refusals, of one commitStream reply (None when absent)."""
    by = line.get('refusedBy') if isinstance(line.get('refusedBy'), dict) else {}
    split = by.get('fence', 0) + by.get('membership', 0) if {'fence', 'membership'} <= set(by) else None
    return line.get('refused'), split


check('revocation: writes after', "the revoked device's commits after the revocation",
      "independent: logs/ipad.stdout.jsonl commitStream replies and `committed` events vs the Mac's `revoked` event",
      {'commitStreamReplies': [{field: line.get(field) for field in ('accepted', 'refused', 'refusedBy', 'failed', 'errors')}
                               for line in commit_streams],
       'committedEventsFromMacRevokedEventOn': len(late_commits), 'committedEventsWholeRun': len(ipad_commits)},
      len(commit_streams) >= 2 and commit_streams[-1].get('accepted') == 0 and (commit_streams[-1].get('refused') or 0) >= 1
      and all(line.get('failed') == 0 and line.get('errors') == [] and stream_refusals(line)[0] == stream_refusals(line)[1]
              for line in commit_streams)
      and len(late_commits) == 0,
      'every commitStream: failed 0, no errors, refused = refusedBy.fence + refusedBy.membership; '
      'the last: accepted 0, refused >= 1; 0 committed events from the revocation on')
# The writers' own loops (2026-11-18): `refused` counts only fence and membership refusals and
# any other failed commit is counted in `failed`, so writes.refused and the expiry refusals mean
# exactly that. `errors` keeps at most the first ten descriptions; `failed` counts them all.
write_loops = {device: [line for line in logs[device] if line.get('op') == 'writeLoop'] for device in ('mac', 'phone')}
unclean_loops = [{'device': device, **{field: line.get(field) for field in ('id', 'refused', 'refusedBy', 'failed', 'errors')}}
                 for device, replies in write_loops.items() for line in replies
                 if not (line.get('failed') == 0 and line.get('errors') == []
                         and stream_refusals(line)[0] == stream_refusals(line)[1])]
check('two-writer audits', 'every write loop of the Mac and the iPhone failed no commit',
      'independent: logs/mac.stdout.jsonl and logs/phone.stdout.jsonl writeLoop replies',
      {'replies': {device: len(replies) for device, replies in write_loops.items()},
       'refusedBy': {kind: sum((line.get('refusedBy') or {}).get(kind, 0) for replies in write_loops.values() for line in replies)
                     for kind in ('fence', 'membership')},
       'unclean': unclean_loops[:10]},
      sum(len(replies) for replies in write_loops.values()) >= 1 and not unclean_loops,
      'at least one reply; every one failed 0, no errors, refused = refusedBy.fence + refusedBy.membership')
successor_grants = [grant for grant in grants if grant['conversationID'] == held and grant['runner'] != ipad
                    and revoked_at is not None and grant['grantedAt'] >= revoked_at]
mac_on_held = [event for event in events('mac', 'committed') if event.get('conversation') == held]
check('revocation: successor', 'grant of the held conversation to another device at the next epoch, and its commits',
      'report: once.counters revoke.successor.accepted; independent: grantLog and logs/mac.stdout.jsonl',
      {'revoke.successor.accepted': once_counter('revoke.successor.accepted'),
       'successorGrants': [{'runner': grant['runner'], 'epoch': grant['epoch']} for grant in successor_grants],
       'macCommitsOnHeldConversationByEpoch': dict(collections.Counter(event.get('epoch') for event in mac_on_held))},
      once_counter('revoke.successor.accepted') == 3 and held_epoch is not None
      and any(grant['runner'] == mac and grant['epoch'] == held_epoch + 1 for grant in successor_grants)
      and sum(1 for event in mac_on_held if event.get('epoch') == held_epoch + 1) >= 3,
      'accepted 3; the Mac granted it at held epoch + 1 after the revocation; >= 3 Mac commits at that epoch')
revoked_history = sorted([(event, 'revoked') for event in ipad_commits if event.get('conversation') == held]
                         + [(event, 'successor') for event in mac_on_held], key=lambda pair: pair[0]['at'])
writer = {}
recount = {'commits': len(revoked_history), 'commitsWithoutEpoch': 0, 'epochWentBackwards': 0, 'twoWriterEpochs': 0}
highest = 0
for event, device in revoked_history:
    epoch = event.get('epoch')
    if epoch is None:
        recount['commitsWithoutEpoch'] += 1
        continue
    if epoch < highest:
        recount['epochWentBackwards'] += 1
    highest = max(highest, epoch)
    if epoch in writer and writer[epoch] != device:
        recount['twoWriterEpochs'] += 1
    writer[epoch] = device
recount['epochs'] = len(writer)
recount['writers'] = len(set(writer.values()))
reported = {field: once_counters.get(f'audit.revoked.{field}') for field in fields}
check('revocation: two-writer audit', 'audit.revoked.* and its recount',
      'report: once.counters; independent: `committed` events of the held conversation in logs/ipad.stdout.jsonl and logs/mac.stdout.jsonl',
      {'reported': reported, 'recount': recount},
      reported == recount and recount['writers'] == 2 and recount['epochs'] >= 2 and recount['commitsWithoutEpoch'] == 0
      and recount['epochWentBackwards'] == 0 and recount['twoWriterEpochs'] == 0,
      'equal; 2 writers, >= 2 epochs, no shared epoch')

# figures for the record, qualified against stress
facts['phaseFigures'] = {phase: {
    'groupDevices': (report.get(phase) or {}).get('groupDevices'),
    'handover.rebalance': phases[phase][1].get('handover.rebalance'),
    'writes.accepted': phases[phase][0].get('writes.accepted'), 'writes.refused': phases[phase][0].get('writes.refused'),
    'expiry.takeOverAfterFreeze': phases[phase][1].get('expiry.takeOverAfterFreeze'),
    'audit.expiry': {field: phases[phase][0].get(f'audit.expiry.{field}') for field in fields},
    'audit.chat': {field: phases[phase][0].get(f'audit.chat.{field}') for field in fields},
    'pairing.probe.total': phases[phase][1].get('pairing.probe.total'),
    'lease.claim': phases[phase][1].get('lease.claim'), 'forward.direct.admission': phases[phase][1].get('forward.direct.admission'),
    'sf.catchUp100': phases[phase][1].get('sf.catchUp100')} for phase in phases}
facts['allStressCounters'] = dict(sorted(stress_counters.items()))

result = {'allChecksOk': all(item['ok'] for item in checks), 'checks': checks, 'facts': facts}
destination.write_text(json.dumps(result, indent=1, sort_keys=True) + '\n')
for item in checks:
    print(('ok   ' if item['ok'] else 'FAIL ') + item['point'] + ' | ' + item['check'] + ' | ' + json.dumps(item['measured'], sort_keys=True)[:600])
print('all checks ok' if result['allChecksOk'] else 'SOME CHECKS FAILED')
raise SystemExit(0 if result['allChecksOk'] else 1)
