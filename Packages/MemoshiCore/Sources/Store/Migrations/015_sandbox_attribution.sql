-- S4.7 sandbox denial attribution. Each Seatbelt instance (one command or one daemon life) is
-- registered before its exec under the fresh tag its profile prints; each kernel denial report
-- read back links to the instance by that tag, or stays explicitly unattributed; reader gaps
-- mark times when reports could not be read (anything the kernel reported then is lost).
-- Retention is bounded by row count (closed gaps per reason; an open gap is always kept);
-- nothing is mapped by time, PID or the running command. A denial of a purged conversation's
-- invocation is never written again, and an `unknown_tag` denial keeps no report text.
CREATE TABLE sandbox_invocations (
  tag TEXT PRIMARY KEY CHECK (length(tag) = 44 AND tag GLOB 'memoshi-inv-*'),
  kind TEXT NOT NULL CHECK (kind IN ('command', 'daemon')),
  bot_id TEXT,
  conversation_id TEXT,
  computer_id TEXT,
  call_id TEXT,
  -- SHA-256 of the argv, never its text.
  command_sha256 TEXT CHECK (command_sha256 IS NULL OR length(command_sha256) = 64),
  started_at INTEGER NOT NULL,
  returned_at INTEGER,
  exit_code INTEGER
);
-- A purged conversation removes its invocations and their denials.
CREATE INDEX sandbox_invocations_conversation ON sandbox_invocations(conversation_id);

CREATE TABLE sandbox_denials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag TEXT NOT NULL CHECK (length(CAST(tag AS BLOB)) <= 256),
  invocation_tag TEXT REFERENCES sandbox_invocations(tag),
  received_at INTEGER NOT NULL,
  reported_at TEXT,
  -- `truncated`: the kernel cut the report (about 1,011 characters) before its tag line; kept
  -- only from a process shown to be Memoshi's, else counted in a `report_truncated` gap alone.
  -- `unknown_tag`: a well-formed tag this host no longer holds; its `report` is empty.
  unattributed TEXT CHECK (unattributed IN ('unknown_tag', 'malformed_tag', 'truncated')),
  report TEXT NOT NULL CHECK (length(CAST(report AS BLOB)) <= 4096),
  duplicates INTEGER NOT NULL CHECK (typeof(duplicates) = 'integer' AND duplicates >= 0),
  -- Received after the invocation's leader returned: a descendant that outlived it. The tag
  -- names the process lineage, not which later command may have driven that descendant.
  after_return INTEGER NOT NULL CHECK (after_return IN (0, 1)),
  CHECK ((invocation_tag IS NULL) = (unattributed IS NOT NULL)),
  CHECK (invocation_tag IS NULL OR invocation_tag = tag)
);
CREATE INDEX sandbox_denials_invocation ON sandbox_denials(invocation_tag);

-- `life` is one monitor (host) life; `sequence` orders its gaps. A gap is written when it opens
-- and rewritten with its end (and count) when it closes or grows. `count`: truncated reports
-- (`report_truncated`), reports in a fast stretch (`report_burst`, `report_rate`), probe
-- reports that never came back (`reports_dropped`, a measured lower bound of the log's loss),
-- or entries the Store or the optional log did not receive (`store_dropped`, `log_dropped`).
CREATE TABLE sandbox_attribution_gaps (
  life TEXT NOT NULL,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  reason TEXT NOT NULL CHECK (
    reason IN (
      'reader_starting', 'reader_stopped', 'reader_idle', 'reader_silent', 'events_lost',
      'report_truncated', 'report_burst', 'report_rate', 'reports_dropped', 'store_dropped',
      'log_dropped')),
  count INTEGER CHECK (count IS NULL OR (typeof(count) = 'integer' AND count >= 0)),
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  PRIMARY KEY (life, sequence)
);
