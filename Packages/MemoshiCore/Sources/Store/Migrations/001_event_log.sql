-- Re-expressed from Draft 3 sidecar/src/store/{db,migrations}.ts; Draft 4 owns this schema.
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO meta (key, value) VALUES ('min_retained_seq', '1');
CREATE TABLE conversation_cursors (
  conversation_id TEXT PRIMARY KEY,
  cseq INTEGER NOT NULL CHECK (cseq >= 0)
);
CREATE TABLE events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  cseq INTEGER,
  ts INTEGER NOT NULL,
  type TEXT NOT NULL,
  type_version INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  actor_kind TEXT NOT NULL,
  actor_id TEXT,
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  bot_id TEXT,
  conversation_id TEXT,
  project_id TEXT,
  task_id TEXT,
  origin TEXT,
  payload TEXT NOT NULL,
  CHECK ((conversation_id IS NULL AND cseq IS NULL) OR
         (conversation_id IS NOT NULL AND cseq > 0))
);
CREATE UNIQUE INDEX events_cseq ON events (conversation_id, cseq)
  WHERE conversation_id IS NOT NULL;
CREATE INDEX events_subject ON events (subject_kind, subject_id, seq);
