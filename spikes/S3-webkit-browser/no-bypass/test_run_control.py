"""Self-test for run-control.py's analyzer, on synthetic run directories only.

  python3 -B -m unittest discover -s spikes/S3-webkit-browser/no-bypass -p 'test_*.py'

Nothing is built or launched, and no recorded spike result is read or rewritten.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

sys.dont_write_bytecode = True
# What the environment held before any test loaded run-control.py; loading it must not change it.
BUILD_ROOT_AT_IMPORT = os.environ.get("MEMOSHI_BUILD_ROOT")
HERE = Path(__file__).resolve().parent
POSITIVE = ["positive-direct", "positive-direct-sw", "positive-gateway", "positive-blank"]
PRODUCT = ["product-fixture", "product-fixture-sw", "product-proxy"]
BLANK = ["product-fixture-blank", "product-proxy-blank"]
FAIL_CLOSED = ["fc-unconfigured-navigate", "fc-unconfigured-suite", "fc-immediate-lab-page",
               "fc-revoked-fixture", "fc-revoked-proxy", "fc-gateway-shutdown", "fc-local-name-grant"]
PAGE = {"results": [{"path": "fetch", "target": "http4", "outcome": "error"}], "ua": "synthetic"}
# What the D135 rows' pages report: the `target=_blank` anchors they clicked or placed.
BLANK_ANCHORS = {"product-fixture-blank": ["d4"], "product-proxy-blank": ["d4", "h"]}
NATIVE_BLANK = ["product-fixture-native-blank", "product-proxy-native-blank"]
# What the T10 crash child left: it died by SIGKILL with a live throwaway profile showing a page.
CRASH_CHILD = {"terminationSignal": 9, "nonPersistent": True, "lockdown": True, "page": "http://127.0.0.1:1/page2",
               "markerNonceMatched": True}
# The owner-free controls added 2026-11-14, in the driver's order after the fail-closed checks.
ADDED = ["positive-native-blank", "product-fixture-native-blank", "product-proxy-native-blank",
         "positive-persistent-seed", "positive-persistent-reopen", "product-persistent-store",
         "product-concurrent-bots", "product-lockdown-suite"]
# The separate-profile controls (D136), after the owner-free controls.
SEPARATE = ["positive-shared-profile", "product-separate-profile", "product-separate-profile-gateway",
            "product-separate-profile-edges", "product-rule-list-sweep"]
SEPARATE_TASKS = ["same-site", "cross-site-link-and-return", "cross-site-redirect-and-sso-return",
                  "told-to-open", "cross-site-blank", "cross-site-script", "window-open", "cross-site-form-get",
                  "cross-site-form-post", "post-back-refused",
                  # D136 review follow-ups F1, F4, F7 and F6.
                  "cross-site-sandboxed-frame", "cross-site-form-ungranted", "cross-site-form-replay",
                  "type-long-native", "type-doubled-space"]
GATEWAY_BOT = "bot.d136.memoshi.test"
SAME_SITE_HOST = "www.d136.memoshi.test"
OTHER_HOST = "other.d136.memoshi-other.test"
GATEWAY_TASKS = ["gw-same-site", "gw-link-and-return", "gw-form-post", "gw-form-ungranted", "gw-form-replay",
                 "gw-opening-fails"]
GATEWAY_SEPARATE_IDS = ["44444444-4444-4444-4444-444444444444", "55555555-5555-5555-5555-555555555555",
                        "66666666-6666-6666-6666-666666666666"]
MARKS = {"A": "d136a-synthetic", "B": "d136b-synthetic", "T": "d136t-synthetic", "G": "d136g-synthetic"}
BOUNDARY = ("boundary:lockdown,denyLocal=none,route=ownedFixture:memoshi.browser.route.{},noGateway")
GATEWAY_BOUNDARY = ("boundary:lockdown,denyLocal=memoshi.browser.deny-local,"
                    "route=gateway:memoshi.browser.route.{},gateway")
PROFILE_ID = "11111111-1111-1111-1111-111111111111"
SEPARATE_IDS = ["22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"]
MARKER = {"localStorage": "synthetic", "cookie": ""}


def seen(task, **values):
    """What a sink page reported to /report."""
    facts = {"task": task, "cookie": "", "storage": None, "storageSeparate": None, "cachedScript": True,
             "serviceWorker": "undefined", "controlled": False}
    facts.update(values)
    return {"seen": json.dumps(facts)}


def separate_profile_rows(scenarios, window):
    """The D136 rows and their owned cookie-sink log, all passing."""
    by_name = {row["name"]: row for row in scenarios}
    events = []

    def request(index, offset, listener, path, query=None, cookie=None, referer=None, method="GET",
                fetch_site=None, form=None):
        events.append({"listener": listener, "method": method, "path": path, "query": query or {},
                       "cookie": cookie, "referer": referer, "secFetchSite": fetch_site,
                       "t": window(index)[0] + offset})
        if form is not None:
            events[-1]["form"] = form

    first = len(scenarios) - len(SEPARATE)
    a, b, t = f"d136={MARKS['A']}", f"d136={MARKS['B']}", f"d136t={MARKS['T']}-kept"
    # A's three cookies: no SameSite, Lax and Strict. A cross-site arrival carries the first two.
    a_all = f"{a}; d136l={MARKS['A']}; d136s={MARKS['A']}"
    a_cross = f"{a}; d136l={MARKS['A']}"
    # Shared profile, outside the boundary: B's cookie, storage, cache and worker all come along.
    by_name["positive-shared-profile"].update(marks=MARKS)
    request(first, 1, "A", "/seed", {"v": MARKS["A"]})
    request(first, 1.1, "A", "/cached.js", {"v": "1"}, a)
    request(first, 2, "B", "/seed", {"v": MARKS["B"], "sw": "1"})
    request(first, 2.1, "B", "/cached.js", {"v": "1"}, b)
    request(first, 3, "A", "/page", {"task": "shared-from"}, a)
    request(first, 4, "B", "/page", {"task": "shared"}, b)
    request(first, 4.1, "B", "/sw-hit", {"u": "page"}, b)
    request(first, 4.2, "B", "/report", seen("shared", cookie=b, storage=MARKS["B"], controlled=True), b)
    # The product run: the bot's profile for same-site moves, returns and its cookie site; a new
    # separate profile for every way of reaching B from A.
    index = first + 1
    profile_codes = ["configuration:true:directFixture", "configuration:true:" + BOUNDARY.format(PROFILE_ID)]
    by_name["product-separate-profile"].update(
        marks=MARKS, profileID=PROFILE_ID, configurationCodes=profile_codes + [
            "navigation:true:separateProfile", "navigation:true:separateProfileDiscarded"],
        separateProfiles=[{"id": i, "codes": ["configuration:true:directFixture",
                                              "configuration:true:" + BOUNDARY.format(i),
                                              "configuration:true:separateProfile"]} for i in SEPARATE_IDS],
        separateOpenAfterRun=False, separateMarkOnDisk=[], profileMarkOnDisk=True,
        separateRuleListsLeft=[], separateStoreIdentifiers=[], exposureConfirmations=2,
        suite={"state": "completed", "taskCount": len(SEPARATE_TASKS), "successfulTasks": list(SEPARATE_TASKS),
               "steps": [{"taskID": "same-site", "index": 0, "operation": "navigate", "succeeded": True,
                          "code": None, "durationMs": 5.0},
                         {"taskID": "type-long-native", "index": 1, "operation": "type", "succeeded": True,
                          "code": None, "durationMs": 9000.0},
                         {"taskID": "type-doubled-space", "index": 1, "operation": "type", "succeeded": True,
                          "code": "invalidResult", "durationMs": 10000.0}]})
    offset = [1.0]
    starts, decisions = [], []

    def at():
        offset[0] += 0.1
        return offset[0]

    def begin(task):
        """The driver saw the runner reach `task`."""
        starts.append({"task": task, "at": window(index)[0] + at()})

    def decided(code):
        """A decision of the bot's own profile, now."""
        decisions.append({"code": code, "at": window(index)[0] + at()})

    def separate_page(task, method="GET", form=None):
        page = f"http://localhost/page?task={task}"
        request(index, at(), "B", "/page", {"task": task, "mark": MARKS["T"]}, method=method, form=form)
        request(index, at(), "B", "/cached.js", {"v": "1"}, t, referer=page)
        request(index, at(), "B", "/report", seen(task, cookie=t, storageSeparate=MARKS["T"] + "-kept"), t,
                referer=page)

    begin("same-site")
    request(index, at(), "A", "/page", {"task": "same-from"}, a)
    request(index, at(), "A2", "/page", {"task": "same"}, a_all, fetch_site="same-site")
    begin("cross-site-link-and-return")
    request(index, at(), "A", "/page", {"task": "link-from"}, a)
    opened = [window(index)[0] + at()]
    separate_page("link")
    request(index, at(), "A", "/page", {"task": "return"}, a_cross, referer="http://localhost:1/",
            fetch_site="cross-site")
    begin("cross-site-redirect-and-sso-return")
    request(index, at(), "A", "/page", {"task": "redirect-from"}, a)
    request(index, at(), "A", "/redirect", {"to": "B"}, a)
    opened.append(window(index)[0] + at())
    separate_page("redirect")
    request(index, at(), "B", "/redirect", {"to": "A"}, t)
    request(index, at(), "A", "/page", {"task": "sso", "code": "d136-code"}, a_cross,
            referer="http://localhost:1/", fetch_site="cross-site")
    begin("told-to-open")
    request(index, at(), "B", "/page", {"task": "command"}, b)
    for task in ("blank", "script", "formget"):
        begin({"blank": "cross-site-blank", "script": "cross-site-script", "formget": "cross-site-form-get"}[task])
        request(index, at(), "A", "/page", {"task": task + "-from"}, a)
        separate_page(task)
    begin("window-open")
    request(index, at(), "A", "/page", {"task": "open-from"}, a)
    begin("cross-site-form-post")
    request(index, at(), "A", "/page", {"task": "formpost-from"}, a)
    separate_page("formpost", method="POST", form={"note": "d136-post"})
    begin("post-back-refused")
    request(index, at(), "A", "/page", {"task": "pb-from"}, a)
    separate_page("pbpage")
    # F1: a sandboxed frame on A moves the top level to B by script: a separate profile.
    begin("cross-site-sandboxed-frame")
    request(index, at(), "A", "/page", {"task": "sframe-from"}, a)
    separate_page("sframe")
    # F4: a form on A to an origin no grant names is refused at the click; nothing is sent.
    begin("cross-site-form-ungranted")
    request(index, at(), "A", "/page", {"task": "ungranted-from"}, a)
    decided("click:false:siteNotGranted")
    # F7: the form leaves for a separate profile with its body; the page left behind replays it
    # into a frame, which its one-use permit no longer covers.
    begin("cross-site-form-replay")
    request(index, at(), "A", "/page", {"task": "formreplay-from"}, a)
    separate_page("formreplay", method="POST", form={"note": "d136-post"})
    decided("form:false:unstagedForm")
    # F6: native typing, on A.
    begin("type-long-native")
    request(index, at(), "A", "/page", {"task": "typed"}, a)
    begin("type-doubled-space")
    request(index, at(), "A", "/page", {"task": "typeddouble"}, a)
    row = by_name["product-separate-profile"]
    row.update(taskStarts=starts, profileDecisions=decisions)
    for profile, when in zip(row["separateProfiles"], opened):
        profile["openedAt"] = when
    by_name["product-separate-profile"]["separateProfiles"][-1]["codes"].append(
        "form:false:separateProfileReturnWithBody")
    # The gateway route, through the owned route to the cookie sink by the gateway's names: a
    # same-site link keeps the profile, a link to B opens a separate profile and the link back
    # returns cross-site, a confirmed POST reaches B separately, an ungranted form and a replayed
    # form are refused, and a redirect's separate opening is refused by the route (F5).
    gateway_index = SEPARATE.index("product-separate-profile-gateway") + first
    g_offset, g_starts, g_decisions, g_opened = [1.0], [], [], []

    def g_at():
        g_offset[0] += 0.1
        return window(gateway_index)[0] + g_offset[0]

    def g_request(listener, host, path, query, cookie=None, method="GET", form=None, referer=None,
                  fetch_site=None):
        events.append({"listener": listener, "host": host, "method": method, "path": path, "query": query,
                       "cookie": cookie, "referer": referer, "secFetchSite": fetch_site, "t": g_at()})
        if form is not None:
            events[-1]["form"] = form

    def g_separate(task, method="GET", form=None):
        kept = f"d136t={MARKS['G']}-kept"
        g_opened.append(g_at())
        g_request("B", OTHER_HOST, "/page", {"task": task, "mark": MARKS["G"]}, method=method, form=form)
        g_request("B", OTHER_HOST, "/report", seen(task, cookie=kept), kept)

    for task, steps in [
        ("gw-same-site", [("A", GATEWAY_BOT, "gw-same-from"), ("A2", SAME_SITE_HOST, "gw-same")]),
        ("gw-link-and-return", [("A", GATEWAY_BOT, "gw-link-from"), "gw-link", "return"]),
        ("gw-form-post", [("A", GATEWAY_BOT, "gw-formpost-from"), "gw-formpost"]),
        ("gw-form-ungranted", [("A", GATEWAY_BOT, "gw-ungranted-from"), "click:false:siteNotGranted"]),
        ("gw-form-replay", [("A", GATEWAY_BOT, "gw-formreplay-from"), "gw-formreplay",
                            "form:false:unstagedForm"]),
        ("gw-opening-fails", [("A", GATEWAY_BOT, "gw-fail-from"), "redirect",
                              "navigation:false:separateProfile.controlRefusedSeparateGateway"]),
    ]:
        g_starts.append({"task": task, "at": g_at()})
        for step in steps:
            if isinstance(step, tuple):
                listener, host, page = step
                g_request(listener, host, "/page", {"task": page}, a_all,
                          fetch_site="same-site" if listener == "A2" else None)
            elif step == "return":
                g_request("A", GATEWAY_BOT, "/page", {"task": "gw-return"}, a_cross,
                          referer=f"http://{OTHER_HOST}/", fetch_site="cross-site")
            elif step == "redirect":
                g_request("A", GATEWAY_BOT, "/redirect", {"to": f"http://{OTHER_HOST}/page?task=gw-failed"}, a_all)
            elif ":" in step:
                g_decisions.append({"code": step, "at": g_at()})
            elif step == "gw-link":
                g_separate(step)
            else:
                g_separate(step, method="POST", form={"note": "d136-post"})
    gateway_codes = ["configuration:true:authenticatedProxy", "configuration:true:" + GATEWAY_BOUNDARY.format(PROFILE_ID)]
    by_name["product-separate-profile-gateway"].update(
        marks=MARKS, profileID=PROFILE_ID, configurationCodes=gateway_codes,
        separateProfiles=[{"id": i, "openedAt": at, "codes": [
            "configuration:true:authenticatedProxy", "configuration:true:" + GATEWAY_BOUNDARY.format(i),
            "configuration:true:separateProfile"]} for i, at in zip(GATEWAY_SEPARATE_IDS, g_opened)],
        separateSeen=[{"id": i, "persistent": False} for i in GATEWAY_SEPARATE_IDS],
        separateOpenAfterRun=False, separateMarkOnDisk=[], separateRuleListsLeft=[], separateStoreIdentifiers=[],
        separateGateway=[], exposureConfirmations=2, refusedOpenings=1, taskStarts=g_starts,
        profileDecisions=g_decisions,
        gateway=[{"host": host, "allowed": True, "reason": None, "at": 1000}
                 for host in (GATEWAY_BOT, SAME_SITE_HOST, OTHER_HOST)],
        suite={"state": "completed", "taskCount": len(GATEWAY_TASKS), "successfulTasks": list(GATEWAY_TASKS),
               "steps": [{"taskID": "gw-opening-fails", "index": 1, "operation": "click", "succeeded": True,
                          "code": "controlRefusedSeparateGateway", "durationMs": 140.0}]})
    # Review F3, F8 and F9 on the signed-in store: a run cancelled during a return, a
    # re-authorization without the separate profile's site, and a file staged in a separate profile.
    edges = SEPARATE.index("product-separate-profile-edges") + first
    request(edges, 1.0, "A", "/page", {"task": "cancel-from"}, a)
    request(edges, 1.5, "B", "/page", {"task": "cancel", "mark": MARKS["T"]})
    request(edges, 3.0, "B", "/page", {"task": "reauthorize"})
    request(edges, 4.0, "B", "/page", {"task": "upload", "mode": "upload"})
    request(edges, 5.0, "B", "/page", {"task": "uploaded"}, method="POST", form={})
    # Spec gap 5: the page that set its cookie after configuration; its frame never loaded.
    request(edges, 6.0, "A", "/page", {"task": "cookieframe", "mode": "cookieframe"})
    by_name["product-separate-profile-edges"].update(
        marks=MARKS, returnDecidedBeforeCancel=True, cancelAt=window(edges)[0] + 2.0, cancelRunState="cancelled",
        profileCommitsAfterCancel=0, separateOpenAfterCancel=False,
        reauthorizeSeparateBefore=True, reauthorizeApplied=True, reauthorizeSeparateAfter=False,
        uploadClick="completed",
        uploadSeparateCodes=["configuration:true:directFixture", "configuration:true:separateProfile",
                             "upload:true:staged", "click:true:allowed", "form:true:allowed"],
        framePrivateAtConfiguration=False,
        frameProfileCodes=["configuration:true:directFixture", "navigation:false:exposureConfirmationRequired"])
    by_name["product-rule-list-sweep"].update(orphanListsBefore=2, orphanListsAfter=0, keptListsAfter=2,
                                              crashListsBefore=2, crashListsAfter=0, crashFilesLeft=[],
                                              crashChild=dict(CRASH_CHILD),
                                              swept=["memoshi.browser.route.x", "memoshi.browser.block-all.x"])
    for name in SEPARATE[1:]:
        by_name[name].pop("page", None)
    return events


def native_page(targets):
    """A native-click probe page that placed one `target=_blank` anchor per target."""
    return {"results": [{"path": "a-target-blank-native", "target": t, "outcome": "placed"} for t in targets],
            "ua": "synthetic"}


def trusted(targets):
    return [{"target": t, "isTrusted": True} for t in targets]


def blank_page(targets):
    """A scripted `target=_blank` probe page that clicked one anchor per target."""
    return {"results": [{"path": "a-target-blank", "target": t, "outcome": "clicked"} for t in targets],
            "ua": "synthetic"}


def load_module(build_root):
    """run-control.py refuses to load without its build root; the analyzer never touches it.
    The root is set only while the module loads, so no later test sees it."""
    with mock.patch.dict(os.environ, {"MEMOSHI_BUILD_ROOT": build_root}):
        spec = importlib.util.spec_from_file_location("run_control", HERE / "run-control.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


def complete_run():
    """Every scenario the driver runs, ten seconds each with a one-second gap, all passing."""
    scenarios, events = [], []

    def window(index):
        return 1000.0 + index * 11, 1010.0 + index * 11

    def event(index, kind, label, first=None):
        record = {"kind": kind, "label": label, "t": window(index)[0] + 1}
        if first:
            record["first"] = first
        events.append(record)

    def tagged(index, tag):
        event(index, "tcp-data", "http4", f"GET /run/scenario/{tag}/x HTTP/1.1")

    for index, name in enumerate(POSITIVE + PRODUCT + BLANK + FAIL_CLOSED + ADDED + SEPARATE):
        start, end = window(index)
        row = {"name": name, "start": start, "end": end}
        if name.startswith("positive"):
            row.update(kind="positiveControl", page=PAGE)
        elif name.startswith("product"):
            row.update(kind="product", page=blank_page(BLANK_ANCHORS[name]) if name in BLANK_ANCHORS else PAGE,
                       gateway=[])
            if "fixture" in name or "persistent" in name:
                row["navigation"] = "started"
        else:
            row.update(kind="failClosed", gateway=[])
        scenarios.append(row)
    for label in ["http4", "http6", "preconnect4", "turn4"]:
        event(0, "tcp-accept", label)
    for label in ["stun-main", "stun6", "quic4"]:
        event(0, "udp", label)
    for tag in ["lan-short", "lan-hex", "lan-octal", "lan-mapped", "dataimg-1", "dataiframe-1",
                "datafetch-1", "datacssimport-1", "datacssbg-1"]:
        tagged(0, tag)
    tagged(1, "sw-fetch")
    event(2, "tcp-accept", "http4")
    scenarios[2]["gateway"] = [{"host": "h.probe.memoshi.invalid", "allowed": True, "reason": None}]
    event(3, "tcp-accept", "http4")
    by_name = {row["name"]: row for row in scenarios}
    by_name["fc-unconfigured-navigate"].update(fixtureRequestsDuring=0, laterResult="refused")
    by_name["fc-unconfigured-suite"].update(fixtureRequestsDuring=0, outcome="refused")
    by_name["fc-immediate-lab-page"].update(immediateLoadStarted=False)
    by_name["fc-revoked-fixture"].update(fixtureRequestsDuring=0, suiteOutcome="refused",
                                         addressResult="refused")
    # What the boundary recorded: the revoked route and gateway gone, every way to the granted site
    # refused, the closed gateway's names failing, the `.local` grant refused by name.
    revoked_boundary = ("boundary:lockdown,denyLocal=memoshi.browser.deny-local.v1,route=none,"
                        "blockAll=memoshi.browser.block-all.x,noGateway")
    by_name["fc-revoked-proxy"].update(
        page={"missing": True, "url": "none"}, revokedBoundary=revoked_boundary,
        suiteOutcome="navigationNotStarted", addressResult="networkBoundary",
        configurationCodes=["configuration:true:authenticatedProxy", "configuration:false:revoked",
                            "configuration:false:" + revoked_boundary,
                            "navigation:false:networkBoundary.routeRulesMissing"])
    by_name["fc-gateway-shutdown"].update(
        gatewayClosedBeforeLoad=True,
        page={"results": [{"path": "fetch", "target": target, "outcome": "err:Load failed"} for target in ("sub", "h")],
              "ua": "synthetic"})
    by_name["fc-local-name-grant"].update(
        page={"missing": True, "url": "none"}, configurationProblem='ControlFailure(message: "configuration '
        'egress.invalidRule")', configurationCodes=["configuration:false:egress.invalidRule",
                                                     "navigation:false:networkBoundary.routeRulesMissing"])
    added = {name: 16 + offset for offset, name in enumerate(ADDED)}
    by_name["positive-native-blank"].update(page=native_page(["d4"]), nativeClicks=trusted(["d4"]))
    event(added["positive-native-blank"], "tcp-accept", "http4")
    by_name["product-fixture-native-blank"].update(page=native_page(["d4"]), nativeClicks=trusted(["d4"]))
    by_name["product-proxy-native-blank"].update(page=native_page(["d4", "h"]),
                                                 nativeClicks=trusted(["d4", "h"]))
    by_name["positive-persistent-seed"].update(storeMarker=MARKER)
    tagged(added["positive-persistent-seed"], "sw-fetch-d4")
    by_name["positive-persistent-reopen"].update(storeMarker=MARKER)
    tagged(added["positive-persistent-reopen"], "swresurrect-d4")
    by_name["product-persistent-store"].update(storeMarker=MARKER,
                                               reopenedImmediateResult="networkBoundary")
    bots_start = window(added["product-concurrent-bots"])[0]
    by_name["product-concurrent-bots"].update(bots=[
        {"name": "product-concurrent-a", "route": "authenticatedProxy", "page": PAGE, "gateway": [],
         "loadStarted": bots_start + 1, "reported": bots_start + 5},
        {"name": "product-concurrent-b", "route": "directFixture", "navigation": "started", "page": PAGE,
         "gateway": [], "loadStarted": bots_start + 1.1, "reported": bots_start + 6}])
    del by_name["product-concurrent-bots"]["page"]
    tasks = ["get-search", "pagination"]
    del by_name["product-lockdown-suite"]["page"]
    by_name["product-lockdown-suite"].update(lockdownActive=True, suite={
        "state": "completed", "taskCount": 2, "successfulTasks": tasks,
        "steps": [{"taskID": t, "index": 0, "operation": "navigate", "succeeded": True, "code": None,
                   "durationMs": 10.0} for t in tasks]})
    timeline = {"schema": "memoshi.s3-no-bypass-control/1", "run": "synthetic", "scenarios": scenarios,
                "failures": [], "realSitesRequested": False, "only": None}
    ports = {"http4": 1, "http6": 2, "preconnect4": 3, "turn4": 4, "stun-main": 5, "stun6": 6,
             "quic4": 7, "badport4": 10080}
    profile_events = separate_profile_rows(scenarios, window)
    liveness = sink_liveness_records(events, profile_events, ports, after=scenarios[-1]["end"] + 3)
    return timeline, events, ports, profile_events, liveness


def sink_liveness_records(events, profile_events, ports, after):
    """Both sinks' `ready` records and, from `after` on, the probe run-control.py sends each
    listener once the driver exited, as each sink logs it; returns liveness.json's facts."""
    udp = {"stun-main", "stun6", "quic4"}
    listeners = [{"label": label, "kind": "udp" if label in udp else "tcp",
                  "host": "::1" if label.endswith("6") else "127.0.0.1", "port": port}
                 for label, port in sorted(ports.items())]
    events.insert(0, {"kind": "ready", "ports": ports, "ownAddresses": {}, "listeners": listeners, "t": 990.0})
    profile_listeners = [{"label": "A", "host": "127.0.0.1", "port": 11}, {"label": "A2", "host": "127.0.0.1", "port": 12},
                         {"label": "B", "host": "127.0.0.1", "port": 13}, {"label": "B", "host": "::1", "port": 13}]
    profile_events.insert(0, {"listener": "ready", "ports": {"A": 11, "A2": 12, "B": 13},
                              "listeners": profile_listeners, "t": 990.0})
    probes = []
    for index, listener in enumerate(listeners):
        token = f"synthetic-{index}"
        peer = str(("127.0.0.1", 60000 + index))
        probe = {"sink": "sinks", "label": listener["label"], "kind": listener["kind"], "token": token,
                 "peer": peer, "sent": True}
        if listener["kind"] == "udp":
            probe["bytes"] = len(token)
            events.append({"kind": "udp", "label": listener["label"], "peer": peer, "bytes": len(token),
                           "stunType": "7379", "t": after + 0.1})
        else:
            events.append({"kind": "tcp-accept", "label": listener["label"], "peer": peer, "t": after + 0.1})
            events.append({"kind": "tcp-data", "label": listener["label"], "peer": peer,
                           "first": "MEMOSHI-S3-LIVENESS " + token, "bytes": 40, "t": after + 0.1})
        probes.append(probe)
    for index, listener in enumerate(profile_listeners):
        token = f"synthetic-p{index}"
        probes.append({"sink": "profile", "label": listener["label"], "host": listener["host"], "token": token,
                       "sent": True, "status": "HTTP/1.1 204 No Content"})
        profile_events.append({"listener": listener["label"], "method": "GET", "path": "/liveness",
                               "query": {"n": token}, "host": "liveness", "cookie": None, "t": after + 0.2})
    return {"nonce": "synthetic", "startedAt": after, "sinksProcessRunning": True,
            "profileSinkProcessRunning": True, "probes": probes}


class AnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.control = load_module(self.scratch.name)
        self.timeline, self.events, self.ports, self.profile_events, self.liveness = complete_run()

    def scenario(self, name):
        return next(row for row in self.timeline["scenarios"] if row["name"] == name)

    def verdict(self, exit_code=0):
        out = Path(self.scratch.name) / "run"
        out.mkdir()
        (out / "timeline.json").write_text(json.dumps(self.timeline))
        (out / "sinks.jsonl").write_text("".join(json.dumps(e) + "\n" for e in self.events))
        (out / "profile-sink.jsonl").write_text("".join(json.dumps(e) + "\n" for e in self.profile_events))
        (out / "sink-ports.json").write_text(json.dumps(self.ports))
        if exit_code is not None:
            (out / "control-exit.json").write_text(json.dumps({"exitCode": exit_code}))
        if self.liveness is not None:
            (out / "liveness.json").write_text(json.dumps(self.liveness))
        self.control.analyze(out)
        # The retained file is the verdict a reader sees.
        return json.loads((out / "summary.json").read_text())["verdict"]

    def assert_no_pass(self, verdict):
        self.assertFalse(verdict["passExcludingRetainedBlankControl"])
        self.assertFalse(verdict["strictPass"])

    def test_a_complete_clean_run_passes(self):
        verdict = self.verdict()
        self.assertTrue(verdict["positiveControlsExercised"])
        self.assertTrue(verdict["productScenariosZeroSinkEvents"])
        self.assertTrue(verdict["failClosedChecksPassed"])
        self.assertTrue(verdict["passExcludingRetainedBlankControl"])
        self.assertTrue(verdict["strictPass"])

    def test_a_product_scenario_whose_probe_never_reported_does_not_pass(self):
        self.scenario("product-fixture")["page"] = {"missing": True, "url": "none"}
        verdict = self.verdict()
        self.assertFalse(verdict["productScenariosZeroSinkEvents"])
        self.assert_no_pass(verdict)

    def test_a_product_scenario_whose_probe_reported_nothing_does_not_pass(self):
        self.scenario("product-proxy")["page"] = {"results": [], "ua": "synthetic"}
        self.assertFalse(self.verdict()["productScenariosZeroSinkEvents"])

    def test_a_product_scenario_whose_navigation_failed_does_not_pass(self):
        self.scenario("product-fixture-sw")["navigation"] = "networkBoundary(denyLocalMissing)"
        self.assertFalse(self.verdict()["productScenariosZeroSinkEvents"])

    def test_a_retained_blank_control_whose_probe_never_reported_is_not_a_strict_pass(self):
        self.scenario("product-proxy-blank")["page"] = {"missing": True, "url": "none"}
        verdict = self.verdict()
        self.assertTrue(verdict["passExcludingRetainedBlankControl"])
        self.assertFalse(verdict["strictPass"])

    def test_a_timeline_truncated_after_the_positive_controls_does_not_pass(self):
        # What the driver leaves behind when it crashes or is timed out: no schema, no failures.
        self.timeline = {"scenarios": self.timeline["scenarios"][:4]}
        verdict = self.verdict(exit_code=124)
        self.assert_no_pass(verdict)
        self.assertFalse(verdict["timelineComplete"])

    def test_a_missing_scenario_does_not_pass(self):
        self.timeline["scenarios"] = [row for row in self.timeline["scenarios"]
                                      if row["name"] != "product-proxy"]
        verdict = self.verdict()
        self.assert_no_pass(verdict)
        self.assertEqual(verdict["missingScenarios"], ["product-proxy"])

    def test_a_driver_that_did_not_exit_cleanly_does_not_pass(self):
        for exit_code in (2, None):
            with self.subTest(exit_code=exit_code):
                self.setUp()
                self.assert_no_pass(self.verdict(exit_code=exit_code))

    def test_a_sink_event_between_two_scenarios_counts_against_the_earlier_one(self):
        product = self.scenario("product-fixture")
        self.events.append({"kind": "tcp-accept", "label": "http4", "t": product["end"] + 0.5})
        verdict = self.verdict()
        self.assertEqual(verdict["perScenarioSinkEvents"]["product-fixture"], 1)
        self.assertFalse(verdict["productScenariosZeroSinkEvents"])
        self.assert_no_pass(verdict)

    def test_a_sink_event_after_the_last_scenario_is_not_dropped(self):
        last = self.timeline["scenarios"][-1]
        self.events.append({"kind": "udp", "label": "quic4", "t": last["end"] + 1.5})
        verdict = self.verdict()
        self.assertEqual(verdict["perScenarioSinkEvents"][last["name"]], 1)
        self.assertFalse(verdict["productScenariosZeroSinkEvents"])
        self.assert_no_pass(verdict)

    def test_a_sink_event_in_a_scenario_without_a_verdict_does_not_pass(self):
        last = self.scenario("fc-local-name-grant")
        last.clear()
        last.update(name="fc-local-name-grant", kind="skipped", reason="no mDNS name registered",
                    start=1165.0, end=1165.0)
        self.events.append({"kind": "tcp-accept", "label": "http4", "t": 1166.0})
        verdict = self.verdict()
        self.assert_no_pass(verdict)
        self.assertEqual(verdict["unattributedSinkEvents"], 1)

    # Owner-free controls added 2026-11-14.

    def test_the_added_controls_are_required_scenarios(self):
        self.timeline["scenarios"] = [row for row in self.timeline["scenarios"]
                                      if row["name"] != "product-lockdown-suite"]
        verdict = self.verdict()
        self.assert_no_pass(verdict)
        self.assertEqual(verdict["missingScenarios"], ["product-lockdown-suite"])

    def test_a_native_blank_control_whose_click_was_not_trusted_is_not_a_strict_pass(self):
        self.scenario("product-proxy-native-blank")["nativeClicks"] = [{"target": "d4", "isTrusted": True},
                                                                     {"target": "h", "isTrusted": False}]
        verdict = self.verdict()
        self.assertTrue(verdict["passExcludingRetainedBlankControl"])
        self.assertFalse(verdict["strictPass"])
        self.assertIn("product-proxy-native-blank", verdict["targetBlankExpectedFailures"])

    def blank_events(self, name, *events):
        """Sink events `(kind, label[, first line])`, a second apart, inside `name`'s window."""
        start = self.scenario(name)["start"]
        for offset, (kind, label, *first) in enumerate(events, 1):
            event = {"kind": kind, "label": label, "t": start + offset}
            if first:
                event["first"] = first[0]
            self.events.append(event)

    def test_one_empty_preconnect_per_anchor_is_the_retained_d135_failure(self):
        # D135's named exception, as recorded: one connection to the link's host and no request;
        # the sink logs its accept and, when its read times out, the read end.
        for name in BLANK + NATIVE_BLANK:
            with self.subTest(name=name):
                self.setUp()
                self.blank_events(name, ("tcp-accept", "http4"), ("tcp-read-end", "http4"))
                verdict = self.verdict()
                self.assertTrue(verdict["retainedBlankOnlyEmptyPreconnect"])
                self.assertTrue(verdict["passExcludingRetainedBlankControl"])
                self.assertFalse(verdict["strictPass"])
                self.assertEqual(verdict["targetBlankExpectedFailures"][name], 2)

    def test_a_request_in_a_retained_blank_control_does_not_pass(self):
        self.blank_events("product-proxy-blank", ("tcp-accept", "http4"),
                          ("tcp-data", "http4", "GET /synthetic/product-proxy-blank/blank-d4.html HTTP/1.1"))
        verdict = self.verdict()
        self.assert_no_pass(verdict)
        self.assertFalse(verdict["retainedBlankOnlyEmptyPreconnect"])

    def test_a_retained_blank_control_beyond_one_empty_connection_per_anchor_does_not_pass(self):
        cases = {"udp": [("udp", "stun-main")],
                 "secondConnection": [("tcp-accept", "http4"), ("tcp-accept", "http4")],
                 "sinkNoAnchorTargets": [("tcp-accept", "http6")],
                 "readEndWithoutConnection": [("tcp-read-end", "http4")]}
        for name in BLANK + NATIVE_BLANK:
            for change, events in cases.items():
                with self.subTest(name=name, change=change):
                    self.setUp()
                    self.blank_events(name, *events)
                    verdict = self.verdict()
                    self.assert_no_pass(verdict)
                    self.assertFalse(verdict["retainedBlankOnlyEmptyPreconnect"])

    def test_a_blank_connection_without_a_reported_anchor_does_not_pass(self):
        self.scenario("product-proxy-blank")["page"] = {"missing": True, "url": "none"}
        self.blank_events("product-proxy-blank", ("tcp-accept", "http4"))
        self.assert_no_pass(self.verdict())

    def test_the_native_blank_positive_needs_a_trusted_click_and_a_connection(self):
        for change in ("untrusted", "noConnection"):
            with self.subTest(change=change):
                self.setUp()
                if change == "untrusted":
                    self.scenario("positive-native-blank")["nativeClicks"] = [{"target": "d4", "isTrusted": False}]
                else:
                    start = self.scenario("positive-native-blank")["start"]
                    self.events = [e for e in self.events if not start <= e["t"] < start + 11]
                verdict = self.verdict()
                self.assertFalse(verdict["positiveControlsExercised"])
                self.assert_no_pass(verdict)

    def test_the_persistent_store_controls_need_a_resurrected_worker_and_a_persisted_marker(self):
        for name, change in [("positive-persistent-seed", "noWorker"), ("positive-persistent-reopen", "noWorker"),
                             ("positive-persistent-reopen", "noMarker")]:
            with self.subTest(name=name, change=change):
                self.setUp()
                row = self.scenario(name)
                if change == "noMarker":
                    row["storeMarker"] = {"localStorage": None, "cookie": ""}
                else:
                    self.events = [e for e in self.events if not row["start"] <= e["t"] < row["start"] + 11]
                verdict = self.verdict()
                self.assertFalse(verdict["positiveControlsExercised"])
                self.assert_no_pass(verdict)

    def test_a_reopened_store_that_lost_its_data_or_loaded_before_configuration_does_not_pass(self):
        for change in ("noMarker", "loadedEarly"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-persistent-store")
                if change == "noMarker":
                    row["storeMarker"] = {"localStorage": "another-run", "cookie": ""}
                else:
                    row["reopenedImmediateResult"] = "loadStarted"
                verdict = self.verdict()
                self.assertFalse(verdict["productScenariosZeroSinkEvents"])
                self.assert_no_pass(verdict)

    def test_concurrent_bots_need_both_probes_overlapping_and_no_sink_event(self):
        for change in ("oneReport", "sequential", "sinkEvent", "oneBot"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-concurrent-bots")
                if change == "oneReport":
                    row["bots"][1]["page"] = {"missing": True, "url": "none"}
                elif change == "sequential":
                    row["bots"][1]["loadStarted"] = row["bots"][0]["reported"] + 1
                    row["bots"][1]["reported"] = row["bots"][0]["reported"] + 3
                elif change == "sinkEvent":
                    self.events.append({"kind": "udp", "label": "stun-main", "t": row["start"] + 3})
                else:
                    row["bots"] = row["bots"][:1]
                verdict = self.verdict()
                self.assertFalse(verdict["productScenariosZeroSinkEvents"])
                self.assert_no_pass(verdict)

    def test_a_concurrent_bot_that_sent_a_local_host_to_its_gateway_does_not_pass(self):
        row = self.scenario("product-concurrent-bots")
        row["bots"][0]["gateway"] = [{"host": "127.0.0.1", "allowed": False, "reason": "ip_literal"}]
        self.assertFalse(self.verdict()["productScenariosZeroSinkEvents"])

    def test_a_product_probe_that_threw_fatally_does_not_pass(self):
        # probe.js records a throw out of its run as `run`/`fatal` and skips every later path.
        fatal = {"path": "run", "target": "fatal", "outcome": "throw:TypeError: synthetic"}
        for name in ("product-fixture", "product-concurrent-bots"):
            with self.subTest(name=name):
                self.setUp()
                page = {"results": PAGE["results"] + [fatal], "ua": "synthetic"}
                row = self.scenario(name)
                if name == "product-concurrent-bots":
                    row["bots"][1]["page"] = page
                else:
                    row["page"] = page
                verdict = self.verdict()
                self.assertFalse(verdict["productScenariosZeroSinkEvents"])
                self.assert_no_pass(verdict)

    def test_an_absent_api_is_listed_and_not_counted_as_measured(self):
        self.scenario("product-fixture-sw")["page"] = {"results": [
            {"path": "serviceworker", "target": "self", "outcome": "available:undefined secure=true"},
            {"path": "serviceworker", "target": "self", "outcome": "err:no navigator.serviceWorker"}],
            "ua": "synthetic"}
        self.scenario("product-proxy")["page"] = {"results": PAGE["results"] + [
            {"path": "webrtc-main", "target": "stun-main", "outcome": "absent"},
            {"path": "worker:rtc-in-worker", "target": "self", "outcome": "undefined"},
            {"path": "webrtc-data-url", "target": "stun-data",
             "outcome": "data-rtc:ReferenceError: Can't find variable: RTCPeerConnection"},
            {"path": "webtransport", "target": "quic4", "outcome": "absent"}], "ua": "synthetic"}
        verdict = self.verdict()
        self.assertEqual(verdict["apiAbsent"], {
            "product-fixture-sw": ["serviceworker self: available:undefined secure=true",
                                   "serviceworker self: err:no navigator.serviceWorker"],
            "product-proxy": ["webrtc-main stun-main: absent", "worker:rtc-in-worker self: undefined",
                              "webrtc-data-url stun-data: data-rtc:ReferenceError: Can't find variable: "
                              "RTCPeerConnection", "webtransport quic4: absent"]})
        # Lockdown removing an API is part of the boundary (D101), so the rows still pass; the
        # list says which paths measured nothing.
        self.assertTrue(verdict["productScenariosZeroSinkEvents"])

    def test_the_lockdown_suite_counts_only_when_it_ran_under_lockdown(self):
        for change in ("noLockdown", "interrupted", "noSteps", "sinkEvent"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-lockdown-suite")
                if change == "noLockdown":
                    row["lockdownActive"] = False
                elif change == "interrupted":
                    row["suite"]["state"] = "interrupted"
                elif change == "noSteps":
                    row["suite"]["steps"] = []
                else:
                    self.events.append({"kind": "tcp-accept", "label": "http4", "t": row["start"] + 3})
                verdict = self.verdict()
                self.assertFalse(verdict["productScenariosZeroSinkEvents"])
                self.assert_no_pass(verdict)

    def test_a_completed_lockdown_suite_without_a_successful_navigation_does_not_pass(self):
        for change in ("allFailed", "onlyOtherStepsSucceeded"):
            with self.subTest(change=change):
                self.setUp()
                suite = self.scenario("product-lockdown-suite")["suite"]
                suite["successfulTasks"] = []
                for step in suite["steps"]:
                    step.update(succeeded=False, code="networkBoundary")
                if change == "onlyOtherStepsSucceeded":
                    suite["steps"].append({"taskID": "get-search", "index": 1, "operation": "snapshot",
                                           "succeeded": True, "code": None, "durationMs": 1.0})
                verdict = self.verdict()
                self.assertFalse(verdict["productScenariosZeroSinkEvents"])
                self.assert_no_pass(verdict)

    def test_a_failed_lockdown_task_is_reported_as_compatibility_not_as_a_bypass(self):
        suite = self.scenario("product-lockdown-suite")["suite"]
        suite["successfulTasks"] = ["get-search"]
        suite["steps"][1]["succeeded"] = False
        suite["steps"][1]["code"] = "elementNotFound"
        verdict = self.verdict()
        self.assertTrue(verdict["passExcludingRetainedBlankControl"])
        compatibility = verdict["lockdownOwnedFixtureSuite"]
        self.assertEqual(compatibility["tasks"], 2)
        self.assertEqual(compatibility["succeeded"], 1)
        self.assertEqual(compatibility["failedTasks"], {"pagination": "navigate:elementNotFound"})
        self.assertTrue(compatibility["lockdownActive"])

    # Separate profile (D136).

    def profile_request(self, listener, path, task):
        return next(e for e in self.profile_events
                    if e["listener"] == listener and e["path"] == path and e["query"].get("task") == task)

    def report(self, task):
        return next(e for e in self.profile_events
                    if e.get("path") == "/report" and json.loads(e["query"]["seen"])["task"] == task)

    def assert_separate_fails(self, verdict):
        self.assertFalse(verdict["productScenariosZeroSinkEvents"])
        self.assertFalse(verdict["separateProfile"]["passed"])
        self.assert_no_pass(verdict)

    def test_a_clean_run_passes_the_separate_profile_checks(self):
        verdict = self.verdict()
        self.assertTrue(verdict["separateProfile"]["passed"])
        for part in ("shared", "direct", "gateway", "edges", "sweep"):
            self.assertTrue(all(verdict["separateProfile"][part].values()), part)

    def test_the_separate_profile_controls_are_required_scenarios(self):
        for name in SEPARATE:
            with self.subTest(name=name):
                self.setUp()
                self.timeline["scenarios"] = [row for row in self.timeline["scenarios"] if row["name"] != name]
                verdict = self.verdict()
                self.assert_no_pass(verdict)
                self.assertEqual(verdict["missingScenarios"], [name])

    def test_a_profile_cookie_reaching_the_other_site_does_not_pass(self):
        for task in ("link", "redirect", "blank", "script", "formget", "formpost"):
            with self.subTest(task=task):
                self.setUp()
                self.profile_request("B", "/page", task)["cookie"] = f"d136={MARKS['B']}"
                self.assert_separate_fails(self.verdict())

    def test_a_separate_page_that_saw_profile_cookie_storage_or_a_worker_does_not_pass(self):
        for change, task in [(c, t) for c in ("storage", "worker", "cookie")
                             for t in ("link", "redirect", "blank", "script", "formget", "formpost")]:
            with self.subTest(change=change, task=task):
                self.setUp()
                report = self.report(task)
                facts = json.loads(report["query"]["seen"])
                if change == "storage":
                    facts["storage"] = MARKS["B"]
                elif change == "worker":
                    facts["controlled"] = True
                else:
                    facts["cookie"] = f"d136={MARKS['B']}"
                report["query"]["seen"] = json.dumps(facts)
                self.assert_separate_fails(self.verdict())

    def test_a_worker_hit_or_a_cached_script_in_the_separate_profile_does_not_pass(self):
        for change in ("swHit", "cached"):
            with self.subTest(change=change):
                self.setUp()
                start = self.scenario("product-separate-profile")["start"]
                if change == "swHit":
                    self.profile_events.append({"listener": "B", "method": "GET", "path": "/sw-hit",
                                                "query": {}, "cookie": None, "t": start + 3.05})
                else:
                    self.profile_events = [e for e in self.profile_events if not (
                        e.get("path") == "/cached.js" and e["listener"] == "B" and start <= e["t"] < start + 11)]
                self.assert_separate_fails(self.verdict())

    def test_a_bot_profile_that_refetched_its_cached_script_does_not_show_the_cache(self):
        start = self.profile_request("B", "/page", "command")["t"]
        self.profile_events.append({"listener": "B", "method": "GET", "path": "/cached.js",
                                    "query": {"v": "1"}, "cookie": f"d136={MARKS['B']}", "t": start + 0.05,
                                    "referer": "http://localhost/page?task=command"})
        self.assert_separate_fails(self.verdict())

    def test_a_same_site_move_without_the_profile_cookie_does_not_pass(self):
        self.profile_request("A2", "/page", "same")["cookie"] = None
        self.assert_separate_fails(self.verdict())

    def test_a_told_to_open_cookie_site_must_use_the_profile(self):
        self.profile_request("B", "/page", "command")["cookie"] = None
        self.assert_separate_fails(self.verdict())

    def test_a_redirect_source_outside_the_profile_does_not_pass(self):
        self.profile_request("A", "/redirect", None)["cookie"] = None
        self.assert_separate_fails(self.verdict())

    def test_a_return_must_arrive_like_a_cross_site_navigation(self):
        for task, change in [(t, c) for t in ("return", "sso")
                             for c in ("strictSent", "laxMissing", "fetchSite", "fullReferer")]:
            with self.subTest(task=task, change=change):
                self.setUp()
                row = self.profile_request("A", "/page", task)
                if change == "strictSent":
                    row["cookie"] += f"; d136s={MARKS['A']}"
                elif change == "laxMissing":
                    row["cookie"] = f"d136={MARKS['A']}"
                elif change == "fetchSite":
                    row["secFetchSite"] = "none"
                else:
                    row["referer"] = "http://localhost:1/page?task=link&mark=secret"
                self.assert_separate_fails(self.verdict())

    def test_the_strict_cookie_must_exist_for_the_check_to_mean_anything(self):
        row = self.profile_request("A2", "/page", "same")
        row["cookie"] = f"d136={MARKS['A']}; d136l={MARKS['A']}"
        self.assert_separate_fails(self.verdict())

    def test_a_post_back_to_the_first_site_must_be_refused(self):
        for change in ("arrived", "notRefused"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-separate-profile")
                if change == "arrived":
                    start = row["start"]
                    self.profile_events.append({"listener": "A", "method": "POST", "path": "/page",
                                                "query": {"task": "postback"}, "cookie": None, "t": start + 9.95})
                else:
                    row["separateProfiles"][-1]["codes"].remove("form:false:separateProfileReturnWithBody")
                self.assert_separate_fails(self.verdict())

    def test_a_return_or_sso_return_outside_the_profile_does_not_pass(self):
        for task, change in [("return", "cookie"), ("sso", "cookie"), ("sso", "code")]:
            with self.subTest(task=task, change=change):
                self.setUp()
                row = self.profile_request("A", "/page", task)
                if change == "cookie":
                    row["cookie"] = None
                else:
                    row["query"]["code"] = "other"
                self.assert_separate_fails(self.verdict())

    def test_a_way_to_the_other_site_that_never_arrived_does_not_pass(self):
        for task in ("link", "redirect", "blank", "script", "formget"):
            with self.subTest(task=task):
                self.setUp()
                self.profile_events.remove(self.profile_request("B", "/page", task))
                self.assert_separate_fails(self.verdict())

    def test_a_window_open_that_reached_the_other_site_with_the_profile_cookie_does_not_pass(self):
        start = self.scenario("product-separate-profile")["start"]
        self.profile_events.append({"listener": "B", "method": "GET", "path": "/page", "query": {"task": "open"},
                                    "cookie": f"d136={MARKS['B']}", "referer": None, "t": start + 9.9})
        self.assert_separate_fails(self.verdict())

    def test_a_refused_post_form_counts_only_when_it_reached_no_profile(self):
        row = self.scenario("product-separate-profile")
        self.profile_events.remove(self.profile_request("B", "/page", "formpost"))
        row["configurationCodes"].append("form:false:separateProfileFormBodyUnavailable")
        row["suite"]["successfulTasks"].remove("cross-site-form-post")
        verdict = self.verdict()
        self.assertTrue(verdict["separateProfile"]["passed"])
        self.assertEqual(verdict["separateProfile"]["formPostOutcome"], "refusedWithoutBody")
        self.setUp()
        self.profile_events.remove(self.profile_request("B", "/page", "formpost"))
        self.scenario("product-separate-profile")["suite"]["successfulTasks"].remove("cross-site-form-post")
        self.assert_separate_fails(self.verdict())

    def test_a_failed_required_task_does_not_pass(self):
        self.scenario("product-separate-profile")["suite"]["successfulTasks"].remove("window-open")
        self.assert_separate_fails(self.verdict())

    def test_too_few_exposure_confirmations_do_not_pass(self):
        self.scenario("product-separate-profile")["exposureConfirmations"] = 0
        self.assert_separate_fails(self.verdict())

    def test_the_sweep_must_remove_leftovers_and_keep_saved_profiles(self):
        for key, value in [("orphanListsBefore", 0), ("orphanListsAfter", 1), ("keptListsAfter", 1)]:
            with self.subTest(key=key):
                self.setUp()
                self.scenario("product-rule-list-sweep")[key] = value
                verdict = self.verdict()
                self.assertFalse(verdict["separateProfile"]["passed"])
                self.assert_no_pass(verdict)

    def test_a_crashed_open_profile_must_be_swept_with_no_files_left(self):
        for key, value in [("crashListsBefore", 0), ("crashListsAfter", 1), ("crashFilesLeft", ["x.crulelist"]),
                           ("crashChild", None), ("crashChild", dict(CRASH_CHILD, terminationSignal=15)),
                           ("crashChild", dict(CRASH_CHILD, nonPersistent=False)),
                           ("crashChild", dict(CRASH_CHILD, lockdown=False)),
                           ("crashChild", dict(CRASH_CHILD, page="")),
                           ("crashChild", dict(CRASH_CHILD, page="http://127.0.0.1:1/other")),
                           ("crashChild", dict(CRASH_CHILD, markerNonceMatched=False)),
                           ("crashChild", {k: v for k, v in CRASH_CHILD.items() if k != "markerNonceMatched"})]:
            with self.subTest(key=key, value=value):
                self.setUp()
                self.scenario("product-rule-list-sweep")[key] = value
                verdict = self.verdict()
                self.assertFalse(verdict["separateProfile"]["passed"])
                self.assert_no_pass(verdict)

    def test_a_separate_profile_left_behind_does_not_pass(self):
        for key, value in [("separateOpenAfterRun", True), ("separateMarkOnDisk", ["Library/x"]),
                           ("profileMarkOnDisk", False), ("separateRuleListsLeft", ["ContentRuleList-x"]),
                           ("separateStoreIdentifiers", [SEPARATE_IDS[0]]), ("separateProfiles", [])]:
            with self.subTest(key=key):
                self.setUp()
                self.scenario("product-separate-profile")[key] = value
                self.assert_separate_fails(self.verdict())

    def test_a_separate_profile_on_another_boundary_does_not_pass(self):
        for change in ("noLockdown", "otherRoute"):
            with self.subTest(change=change):
                self.setUp()
                codes = self.scenario("product-separate-profile")["separateProfiles"][1]["codes"]
                if change == "noLockdown":
                    codes[1] = codes[1].replace("boundary:lockdown", "boundary:noLockdown")
                else:
                    codes[0] = "configuration:true:authenticatedProxy"
                self.assert_separate_fails(self.verdict())

    def gateway_request(self, listener, task, path="/page"):
        start = self.scenario("product-separate-profile-gateway")["start"]
        return next(e for e in self.profile_events if e["t"] >= start and e["listener"] == listener
                    and e["path"] == path and e["query"].get("task") == task)

    def gateway_step(self, task, operation):
        suite = self.scenario("product-separate-profile-gateway")["suite"]
        return next(s for s in suite["steps"] if s["taskID"] == task and s["operation"] == operation)

    def test_the_gateway_separate_profile_must_keep_the_route_and_the_sites_apart(self):
        boundary = GATEWAY_BOUNDARY.format(GATEWAY_SEPARATE_IDS[0])
        other_identity = {"host": OTHER_HOST, "allowed": True, "reason": None, "bot": "browser-review-x"}
        for key, value in [("separateProfiles", []), ("separateSeen", [{"id": "x", "persistent": True}]),
                           ("separateSeen", []), ("separateGateway", [other_identity]),
                           ("separateOpenAfterRun", True), ("separateMarkOnDisk", ["Library/x"]),
                           ("separateRuleListsLeft", ["ContentRuleList-x"]),
                           ("separateStoreIdentifiers", [GATEWAY_SEPARATE_IDS[0]]), ("exposureConfirmations", 0),
                           ("gateway", []),
                           ("gateway", [{"host": OTHER_HOST, "allowed": False, "reason": "x", "at": 1}]),
                           ("gateway", [{"host": "elsewhere.example", "allowed": True, "reason": None, "at": 1}]),
                           ("configurationCodes", ["configuration:true:directFixture",
                                                   "configuration:true:" + BOUNDARY.format(PROFILE_ID)]),
                           ("separateProfile0", boundary.replace(",gateway", ",noGateway")),
                           ("successfulTasks", "gw-link-and-return")]:
            with self.subTest(key=key, value=value):
                self.setUp()
                row = self.scenario("product-separate-profile-gateway")
                if key == "separateProfile0":
                    row["separateProfiles"][0]["codes"][1] = "configuration:true:" + value
                elif key == "successfulTasks":
                    row["suite"]["successfulTasks"].remove(value)
                else:
                    row[key] = value
                self.assert_separate_fails(self.verdict())

    def test_the_gateway_pages_show_the_profile_choice_by_their_cookies(self):
        for change in ("sameSiteWithoutCookie", "linkWithProfileCookie", "linkNotReached", "returnWithStrict",
                       "returnSameSite", "otherSiteCookie", "pageNotByName"):
            with self.subTest(change=change):
                self.setUp()
                if change == "sameSiteWithoutCookie":
                    self.gateway_request("A2", "gw-same")["cookie"] = None
                elif change == "linkWithProfileCookie":
                    self.report_in_gateway("gw-link", cookie=f"d136={MARKS['B']}")
                elif change == "linkNotReached":
                    self.profile_events.remove(self.gateway_request("B", "gw-link"))
                elif change == "returnWithStrict":
                    self.gateway_request("A", "gw-return")["cookie"] += f"; d136s={MARKS['A']}"
                elif change == "returnSameSite":
                    self.gateway_request("A", "gw-return")["secFetchSite"] = "same-site"
                elif change == "otherSiteCookie":
                    self.gateway_request("B", "gw-formpost")["cookie"] = f"d136={MARKS['B']}"
                else:
                    self.gateway_request("B", "gw-link")["host"] = "localhost:13"
                self.assert_separate_fails(self.verdict())

    def report_in_gateway(self, task, **values):
        start = self.scenario("product-separate-profile-gateway")["start"]
        report = next(e for e in self.profile_events if e["t"] >= start and e["path"] == "/report"
                      and json.loads(e["query"]["seen"])["task"] == task)
        report["query"] = seen(task, **values)

    def test_the_gateway_forms_must_be_refused_where_no_grant_or_permit_covers_them(self):
        for change in ("ungrantedSent", "ungrantedNoRefusal", "ungrantedAtGateway", "replayArrived",
                       "replayNoRefusal", "postNeverArrived"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-separate-profile-gateway")
                if change == "ungrantedSent":
                    self.profile_events.append({"listener": "A", "host": "ungranted.d136.memoshi-third.test",
                                                "method": "POST", "path": "/page", "query": {"task": "gw-ungranted"},
                                                "cookie": None, "t": row["start"] + 5})
                elif change == "ungrantedNoRefusal":
                    row["profileDecisions"] = [d for d in row["profileDecisions"]
                                               if d["code"] != "click:false:siteNotGranted"]
                elif change == "ungrantedAtGateway":
                    row["gateway"].append({"host": "ungranted.d136.memoshi-third.test", "allowed": False,
                                           "reason": "host_not_allowed", "at": 1})
                elif change == "replayArrived":
                    self.profile_events.append({"listener": "B", "host": OTHER_HOST, "method": "POST", "path": "/page",
                                                "query": {"task": "gw-formreplay"}, "form": {"note": "d136-replay"},
                                                "cookie": None, "t": row["start"] + 5})
                elif change == "replayNoRefusal":
                    row["profileDecisions"] = [d for d in row["profileDecisions"]
                                               if d["code"] != "form:false:unstagedForm"]
                else:
                    self.profile_events.remove(self.gateway_request("B", "gw-formpost"))
                self.assert_separate_fails(self.verdict())

    def test_a_refused_separate_opening_must_be_reported_at_once_with_its_own_code(self):
        # D136 review F5: the old commit wait ran 30 s and reported `navigationFailed`.
        for change in ("slow", "navigationFailed", "notExpected", "notRefused", "unrecorded", "noRedirect",
                       "reachedOther"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-separate-profile-gateway")
                step = self.gateway_step("gw-opening-fails", "click")
                if change == "slow":
                    step["durationMs"] = 30_000.0
                elif change == "navigationFailed":
                    step["code"] = "navigationFailed"
                elif change == "notExpected":
                    step["succeeded"] = False
                elif change == "notRefused":
                    row["refusedOpenings"] = 0
                elif change == "unrecorded":
                    row["profileDecisions"] = [d for d in row["profileDecisions"]
                                               if not d["code"].startswith("navigation:false:separateProfile.")]
                elif change == "noRedirect":
                    self.profile_events.remove(self.gateway_request("A", None, path="/redirect"))
                else:
                    self.profile_events.append({"listener": "B", "host": OTHER_HOST, "method": "GET", "path": "/page",
                                                "query": {"task": "gw-failed"}, "cookie": None,
                                                "t": row["start"] + 9})
                self.assert_separate_fails(self.verdict())

    def test_the_shared_profile_positive_needs_cookie_storage_cache_and_worker(self):
        for change in ("cookie", "storage", "cache", "worker"):
            with self.subTest(change=change):
                self.setUp()
                start = self.scenario("positive-shared-profile")["start"]
                window = [e for e in self.profile_events if start <= e["t"] < start + 11]
                if change == "cookie":
                    next(e for e in window if e["path"] == "/page" and e["listener"] == "B")["cookie"] = None
                elif change == "storage":
                    self.report("shared")["query"] = seen("shared", cookie=f"d136={MARKS['B']}", controlled=True)
                elif change == "cache":
                    self.profile_events.append({"listener": "A", "method": "GET", "path": "/cached.js",
                                                "query": {"v": "1"}, "cookie": None, "t": start + 3.05})
                else:
                    self.profile_events.remove(next(e for e in window if e["path"] == "/sw-hit"))
                verdict = self.verdict()
                self.assertFalse(verdict["positiveControlsExercised"])
                self.assert_no_pass(verdict)

    # D136 review follow-ups (F1, F3, F4, F6, F7, F8, F9).

    def suite_step(self, task, operation):
        suite = self.scenario("product-separate-profile")["suite"]
        return next(s for s in suite["steps"] if s["taskID"] == task and s["operation"] == operation)

    def task_start(self, task):
        return next(s["at"] for s in self.scenario("product-separate-profile")["taskStarts"] if s["task"] == task)

    def test_the_follow_up_tasks_are_required(self):
        for task in ("cross-site-sandboxed-frame", "cross-site-form-ungranted", "cross-site-form-replay",
                     "type-long-native", "type-doubled-space"):
            with self.subTest(task=task):
                self.setUp()
                self.scenario("product-separate-profile")["suite"]["successfulTasks"].remove(task)
                self.assert_separate_fails(self.verdict())

    def test_a_sandboxed_frame_move_that_kept_the_profile_does_not_pass(self):
        # F1: the frame's script move must open B in a separate profile, never with B's cookie.
        for change in ("profileCookie", "notReached"):
            with self.subTest(change=change):
                self.setUp()
                page = self.profile_request("B", "/page", "sframe")
                if change == "profileCookie":
                    page["cookie"] = f"d136={MARKS['B']}"
                else:
                    self.profile_events.remove(page)
                self.assert_separate_fails(self.verdict())

    def test_an_ungranted_form_must_be_refused_at_the_click_and_reach_nothing(self):
        # F4: refused as `siteNotGranted`, no separate profile opened for it, nothing sent.
        for change in ("noRefusal", "refusalElsewhere", "sent", "separateOpened", "unattributable", "notSeen"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-separate-profile")
                refusal = next(d for d in row["profileDecisions"] if d["code"] == "click:false:siteNotGranted")
                if change == "noRefusal":
                    row["profileDecisions"].remove(refusal)
                elif change == "refusalElsewhere":
                    refusal["at"] = self.task_start("cross-site-sandboxed-frame") + 0.01
                elif change == "sent":
                    self.profile_events.append({"listener": "A", "method": "POST", "path": "/page",
                                                "query": {"task": "ungranted"}, "form": {"note": "d136-post"},
                                                "cookie": None, "t": refusal["at"] + 0.01})
                elif change == "separateOpened":
                    row["separateProfiles"][0]["openedAt"] = refusal["at"]
                elif change == "unattributable":
                    del row["separateProfiles"][0]["openedAt"]
                else:
                    row["taskStarts"] = [s for s in row["taskStarts"] if s["task"] != "cross-site-form-ungranted"]
                self.assert_separate_fails(self.verdict())

    def test_a_form_replayed_after_its_hand_off_must_be_refused(self):
        # F7: the permit left with the form; the replay is refused and never reaches B.
        for change in ("replayArrived", "noRefusal", "refusalElsewhere", "noHandOff"):
            with self.subTest(change=change):
                self.setUp()
                row = self.scenario("product-separate-profile")
                refusal = next(d for d in row["profileDecisions"] if d["code"] == "form:false:unstagedForm")
                if change == "replayArrived":
                    self.profile_events.append({"listener": "B", "method": "POST", "path": "/page",
                                                "query": {"task": "formreplay", "mark": MARKS["T"]},
                                                "form": {"note": "d136-replay"}, "cookie": None,
                                                "t": refusal["at"]})
                elif change == "noRefusal":
                    row["profileDecisions"].remove(refusal)
                elif change == "refusalElsewhere":
                    refusal["at"] = self.task_start("cross-site-form-ungranted") + 0.01
                else:
                    self.profile_events.remove(self.profile_request("B", "/page", "formreplay"))
                self.assert_separate_fails(self.verdict())

    def test_native_typing_must_match_the_field_exactly(self):
        # F6: 300 characters match; a field that doubles a space fails with `invalidResult`.
        for task, code in [("type-long-native", "invalidResult"), ("type-doubled-space", None),
                           ("type-doubled-space", "staleSnapshot")]:
            with self.subTest(task=task, code=code):
                self.setUp()
                self.suite_step(task, "type")["code"] = code
                self.assert_separate_fails(self.verdict())

    def test_the_separate_profile_edges_are_a_required_scenario(self):
        self.timeline["scenarios"] = [row for row in self.timeline["scenarios"]
                                      if row["name"] != "product-separate-profile-edges"]
        verdict = self.verdict()
        self.assert_no_pass(verdict)
        self.assertEqual(verdict["missingScenarios"], ["product-separate-profile-edges"])

    def test_the_separate_profile_edges_must_each_hold(self):
        start = self.scenario("product-separate-profile-edges")["start"]
        cases = [
            # F3: cancelled during a return, nothing commits in the bot's profile afterwards, the
            # return never arrives, and no separate profile opens after the task ended.
            ("returnDecidedBeforeCancel", False), ("cancelAt", None), ("cancelRunState", "completed"),
            ("profileCommitsAfterCancel", 2), ("profileCommitsAfterCancel", None),
            ("returnArrived", True), ("separateOpenAfterCancel", True),
            ("separateOpenAfterCancel", None),
            # F8: re-authorized without the other site, no separate profile stays open.
            ("reauthorizeSeparateBefore", False), ("reauthorizeApplied", False),
            ("reauthorizeSeparateAfter", True),
            # F9: the staged file's confirmation reaches the separate profile; its form is allowed.
            ("uploadSeparateCodes", ["configuration:true:separateProfile", "upload:true:staged",
                                     "click:false:exposureConfirmationRequired"]),
            ("uploadSeparateCodes", ["configuration:true:separateProfile", "click:true:allowed",
                                     "form:true:allowed"]),
            ("uploadSubmitted", False),
            # Spec gap 5: the page's own cookie makes it hold private data; its other-origin frame
            # is refused, though the profile held nothing when it was configured.
            ("framePrivateAtConfiguration", True), ("frameProfileCodes", ["configuration:true:directFixture"]),
            ("frameEmbedded", True), ("framePageMissing", True)]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.setUp()
                row = self.scenario("product-separate-profile-edges")
                if key == "returnArrived":
                    self.profile_events.append({"listener": "A", "method": "GET", "path": "/page",
                                                "query": {"task": "cancelreturn"}, "cookie": None, "t": start + 2.5})
                elif key == "uploadSubmitted":
                    self.profile_events.remove(self.profile_request("B", "/page", "uploaded"))
                elif key == "frameEmbedded":
                    self.profile_events.append({"listener": "B", "method": "GET", "path": "/page",
                                                "query": {"task": "embedded"}, "cookie": None, "t": start + 6.5})
                elif key == "framePageMissing":
                    self.profile_events.remove(self.profile_request("A", "/page", "cookieframe"))
                else:
                    row[key] = value
                self.assert_separate_fails(self.verdict())

    # Fail-closed checks: each is judged from what it recorded.

    def test_each_fail_closed_check_is_judged_from_what_it_recorded(self):
        revoked = "configuration:false:revoked"
        reached = {"results": [{"path": "fetch", "target": "h", "outcome": "status:200"}], "ua": "synthetic"}
        cases = [
            ("fc-revoked-proxy", "revokedBoundary", "boundary:lockdown,denyLocal=x,route=gateway:x,gateway"),
            ("fc-revoked-proxy", "suiteOutcome", "loaded"), ("fc-revoked-proxy", "addressResult", "loadStarted"),
            ("fc-revoked-proxy", "page", reached), ("fc-revoked-proxy", "codes", [revoked]),
            ("fc-revoked-proxy", "codes", ["navigation:false:networkBoundary.routeRulesMissing"]),
            ("fc-revoked-proxy", "gateway", [{"host": "granted.probe.memoshi.invalid", "allowed": True}]),
            ("fc-gateway-shutdown", "gatewayClosedBeforeLoad", False),
            ("fc-gateway-shutdown", "page", {"missing": True, "url": "none"}),
            ("fc-gateway-shutdown", "page", reached),
            ("fc-gateway-shutdown", "page", {"results": [{"path": "fetch", "target": "h", "outcome": "err:x"}],
                                             "ua": "synthetic"}),
            ("fc-gateway-shutdown", "gateway", [{"host": "h.probe.memoshi.invalid", "allowed": False}]),
            # Any configuration error no longer counts: it must be the gateway's refusal of the name.
            ("fc-local-name-grant", "codes", ["configuration:false:hostOperationFailed",
                                              "navigation:false:networkBoundary.routeRulesMissing"]),
            ("fc-local-name-grant", "codes", ["configuration:false:egress.invalidRule",
                                              "configuration:true:authenticatedProxy",
                                              "navigation:false:networkBoundary.routeRulesMissing"]),
            ("fc-local-name-grant", "page", reached),
            ("fc-unconfigured-navigate", "laterResult", None)]
        for name, key, value in cases:
            with self.subTest(name=name, key=key, value=value):
                self.setUp()
                self.scenario(name)["configurationCodes" if key == "codes" else key] = value
                verdict = self.verdict()
                self.assertFalse(verdict["failClosedChecksPassed"])
                self.assert_no_pass(verdict)

    def test_a_fail_closed_check_the_analyzer_does_not_know_never_passes(self):
        self.scenario("fc-revoked-proxy")["name"] = "fc-something-new"
        verdict = self.verdict()
        self.assertFalse(verdict["failClosedChecksPassed"])
        self.assert_no_pass(verdict)

    def test_a_proxy_page_that_ran_and_reached_nothing_is_refused_too(self):
        self.scenario("fc-revoked-proxy")["page"] = {
            "results": [{"path": "fetch", "target": "h", "outcome": "err:Load failed"}], "ua": "synthetic"}
        self.assertTrue(self.verdict()["failClosedChecksPassed"])

    # Sink liveness: an empty log counts only from a sink that was still alive at the end.

    def test_a_run_without_liveness_facts_is_not_a_pass(self):
        self.liveness = None
        verdict = self.verdict()
        self.assertFalse(verdict["sinksAlive"])
        self.assert_no_pass(verdict)

    def test_a_listener_that_did_not_log_its_probe_was_dead(self):
        for sink, label in [("sinks", "http4"), ("sinks", "quic4"), ("profile", "B")]:
            with self.subTest(sink=sink, label=label):
                self.setUp()
                probe = next(p for p in self.liveness["probes"] if p["sink"] == sink and p["label"] == label)
                if sink == "sinks":
                    self.events = [e for e in self.events if e.get("peer") != probe["peer"]]
                else:
                    self.profile_events = [e for e in self.profile_events
                                           if (e.get("query") or {}).get("n") != probe["token"]]
                verdict = self.verdict()
                self.assertFalse(verdict["sinksAlive"])
                self.assertTrue(any(label in missing for missing in verdict["sinkLiveness"]["missing"]))
                self.assert_no_pass(verdict)

    def test_an_unsent_probe_or_a_stopped_sink_process_is_not_alive(self):
        for change in ("unsent", "sinksStopped", "profileStopped", "noListenerList"):
            with self.subTest(change=change):
                self.setUp()
                if change == "unsent":
                    self.liveness["probes"][0]["sent"] = False
                elif change == "sinksStopped":
                    self.liveness["sinksProcessRunning"] = False
                elif change == "profileStopped":
                    self.liveness["profileSinkProcessRunning"] = False
                else:
                    del self.events[0]["listeners"]
                verdict = self.verdict()
                self.assertFalse(verdict["sinksAlive"])
                self.assert_no_pass(verdict)

    def test_a_probe_is_no_scenario_event_but_an_earlier_event_from_its_address_is(self):
        verdict = self.verdict()
        self.assertTrue(verdict["sinksAlive"])
        self.assertEqual(verdict["perScenarioSinkEvents"][self.timeline["scenarios"][-1]["name"]], 0)
        self.setUp()
        product = self.scenario("product-fixture")
        peer = self.liveness["probes"][0]["peer"]
        self.events.append({"kind": "tcp-accept", "label": "http4", "peer": peer, "t": product["start"] + 1})
        verdict = self.verdict()
        self.assertEqual(verdict["perScenarioSinkEvents"]["product-fixture"], 1)
        self.assert_no_pass(verdict)

    def test_a_development_run_of_some_scenarios_is_never_a_complete_control(self):
        self.timeline["only"] = ["product-separate-profile-gateway"]
        verdict = self.verdict()
        self.assertFalse(verdict["timelineComplete"])
        self.assertEqual(verdict["scenarioFilter"], ["product-separate-profile-gateway"])
        self.assert_no_pass(verdict)

    def test_fetch_metadata_may_be_absent_only_on_the_plain_http_gateway_route(self):
        # WebKit sends it only to potentially trustworthy origins (the loopback fixtures).
        self.gateway_request("A", "gw-return")["secFetchSite"] = None
        self.assertTrue(self.verdict()["separateProfile"]["gateway"]["returnArrivesCrossSite"])
        self.setUp()
        self.profile_request("A", "/page", "return")["secFetchSite"] = None
        self.assert_separate_fails(self.verdict())


class HarnessTests(unittest.TestCase):
    """The run-control.py steps around the analyzer, with every subprocess replaced."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.control = load_module(self.scratch.name)

    def test_loading_run_control_leaves_the_environment_alone(self):
        self.assertEqual(os.environ.get("MEMOSHI_BUILD_ROOT"), BUILD_ROOT_AT_IMPORT)

    def test_a_state_whose_scratch_is_not_owned_below_the_build_root_is_refused(self):
        for scratch in (self.root / "elsewhere" / "S3NoBypass-x", self.root / "other-x"):
            with self.subTest(scratch=str(scratch)):
                scratch.mkdir(parents=True, mode=0o700)
                state = self.root / (scratch.name + ".json")
                state.write_text(json.dumps({"scratch": str(scratch)}))
                with self.assertRaises(RuntimeError):
                    self.control.load_state(state)
        owned = self.root / "S3NoBypass-owned"
        owned.mkdir(mode=0o700)
        (self.root / "owned.json").write_text(json.dumps({"scratch": str(owned)}))
        self.assertEqual(self.control.load_state(self.root / "owned.json"), {"scratch": str(owned)})

    def test_a_build_without_a_readable_head_stops_before_compiling(self):
        run, package = self.root / "run", self.root / "package"
        run.mkdir()
        (package / "Sources/S3NoBypassControl").mkdir(parents=True)
        state = {"run": str(run), "package": str(package), "scratch": str(self.root)}
        commands = []

        def fake_run(command, **kwargs):
            commands.append(command)
            if command[-2:] == ["rev-parse", "HEAD"]:
                if kwargs.get("check"):
                    raise subprocess.CalledProcessError(128, command)
                return subprocess.CompletedProcess(command, 128, stdout="", stderr="fatal")
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with mock.patch.object(self.control.subprocess, "run", fake_run):
            with self.assertRaises(subprocess.CalledProcessError):
                self.control.build(state, "worktree")
        self.assertFalse((run / "sources-worktree.json").exists())
        self.assertEqual([command for command in commands if "swift" in command[0]], [])

    def build_with_status(self, status, tree="head"):
        """Runs build() with git and swift replaced; `status` is `git status --porcelain` output."""
        run, package = self.root / "run", self.root / "package"
        run.mkdir(exist_ok=True)
        (package / "Sources/S3NoBypassControl").mkdir(parents=True, exist_ok=True)
        state = {"run": str(run), "package": str(package), "scratch": str(self.root)}
        commands = []

        def fake_run(command, **kwargs):
            commands.append(command)
            if command[-2:] == ["rev-parse", "HEAD"]:
                return subprocess.CompletedProcess(command, 0, stdout="0" * 40 + "\n", stderr="")
            if "status" in command:
                return subprocess.CompletedProcess(command, 0, stdout=status, stderr="")
            if "show" in command:
                return subprocess.CompletedProcess(command, 0, stdout=b"// HEAD\n", stderr=b"")
            return subprocess.CompletedProcess(command, 1, stdout="", stderr="")

        with mock.patch.object(self.control.subprocess, "run", fake_run):
            try:
                return self.control.build(state, tree), commands, run
            except RuntimeError as error:
                return error, commands, run

    def test_a_head_build_refuses_packages_that_differ_from_head(self):
        # It compiles HEAD's app files against the worktree packages; those must be HEAD's too.
        status = (" M Packages/MemoshiApp/Sources/AppCore/BrowserAuthorization.swift\n"
                  "?? Packages/MemoshiApp/Sources/AppCore/BrowserLaneSequencer.swift\n")
        result, commands, run = self.build_with_status(status)
        self.assertIsInstance(result, RuntimeError)
        self.assertIn("Packages/MemoshiApp/Sources/AppCore/BrowserAuthorization.swift", str(result))
        self.assertIn("Packages/MemoshiApp/Sources/AppCore/BrowserLaneSequencer.swift", str(result))
        self.assertFalse((run / "sources-head.json").exists())
        self.assertEqual([c for c in commands if "swift" in c[0] or "show" in c], [])
        status_command = next(c for c in commands if "status" in c)
        for package in ("MemoshiApp", "MemoshiIPC", "MemoshiCore", "MemoshiProtocol", "MemoshiMLS"):
            self.assertIn("Packages/" + package, status_command)

    def test_a_head_build_with_head_packages_goes_on_to_compile(self):
        result, commands, run = self.build_with_status("")
        self.assertEqual(result, 1)
        self.assertTrue(json.loads((run / "sources-head.json").read_text())["packagesMatchHead"])
        self.assertTrue(any("swift" in c[0] for c in commands))

    def test_the_carrier_packages_are_every_repository_package_it_depends_on(self):
        self.assertEqual(self.control.carrier_packages(),
                         ["MemoshiApp", "MemoshiCore", "MemoshiIPC", "MemoshiMLS", "MemoshiProtocol"])

    def test_the_parent_closes_every_helper_log_it_opened(self):
        handles, processes = [], []

        def fake_popen(command, stdout=None, **kwargs):
            handles.append(stdout)
            return types.SimpleNamespace(command=command)

        with mock.patch.object(self.control.subprocess, "Popen", fake_popen), \
                mock.patch.object(self.control, "resolve_numeric", lambda name: ["127.0.0.1"]):
            self.control.register_names(self.root, {"http4": 1}, "synthetic", processes)
        self.assertEqual(len(handles), 2)
        self.assertEqual(len(processes), 2)
        self.assertTrue(all(handle.closed for handle in handles))

    def test_run_takes_local_names_and_a_scenario_filter_of_known_scenarios_only(self):
        options = self.control.run_options
        self.assertEqual(options([]), (True, None))
        self.assertEqual(options(["--no-local-names"]), (False, None))
        self.assertEqual(options(["--only", "fc-revoked-proxy,product-separate-profile-gateway"]),
                         (True, ["fc-revoked-proxy", "product-separate-profile-gateway"]))
        self.assertEqual(options(["--no-local-names", "--only", "fc-revoked-proxy"]), (False, ["fc-revoked-proxy"]))
        for refused in (["--only"], ["--only", "no-such-scenario"], ["--only", ""], ["--only", "fc-revoked-proxy", "x"],
                        ["--only", "fc-revoked-proxy", "--no-local-names"], ["--other"]):
            with self.subTest(arguments=refused):
                self.assertIsNone(options(refused))


class SinkLivenessProbeTests(unittest.TestCase):
    """run-control.py's liveness probe against the real profile-sink.py (loopback listeners only)."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.control = load_module(self.scratch.name)

    def test_every_live_listener_logs_its_own_probe_and_a_stopped_one_logs_none(self):
        log, ports = self.root / "profile-sink.jsonl", self.root / "profile-ports.json"
        sink = subprocess.Popen([sys.executable, "-B", str(HERE / "profile-sink.py"), str(log), str(ports)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (sink.kill(), sink.wait()))
        self.control.wait_file(ports)
        deadline = time.time() + 10
        while not self.control.ready_record(log, "listener") and time.time() < deadline:
            time.sleep(0.05)
        probes = self.control.probe_liveness(self.root / "no-sinks.jsonl", log, "live")
        self.assertEqual([(p["label"], p["host"]) for p in probes],
                         [("A", "127.0.0.1"), ("A2", "127.0.0.1"), ("B", "127.0.0.1"), ("B", "::1")])
        self.assertTrue(all(p["sent"] and p["status"].endswith("204 No Content") for p in probes), probes)
        records = [json.loads(line) for line in log.read_text().splitlines()]
        logged = {(r["listener"], r["query"]["n"]) for r in records if r.get("path") == "/liveness"}
        self.assertEqual(logged, {(p["label"], p["token"]) for p in probes})
        sink.terminate()
        sink.wait()
        stopped = self.control.probe_liveness(self.root / "no-sinks.jsonl", log, "after")
        self.assertTrue(stopped and not any(p["sent"] for p in stopped), stopped)


if __name__ == "__main__":
    unittest.main()
