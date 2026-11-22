CREATE TABLE approval_bindings (
  approval_id TEXT PRIMARY KEY REFERENCES approvals(id),
  card_id TEXT NOT NULL UNIQUE REFERENCES cards(id),
  runtime_task_key TEXT NOT NULL,
  operation TEXT NOT NULL,
  UNIQUE (approval_id, runtime_task_key)
);
CREATE TABLE bot_policy (
  bot_id TEXT PRIMARY KEY,
  permission_mode TEXT NOT NULL CHECK (permission_mode IN ('ask_first', 'auto', 'bypass')),
  active INTEGER NOT NULL CHECK (active IN (0, 1))
);
CREATE TABLE policy_control (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  kill_switch INTEGER NOT NULL CHECK (kill_switch IN (0, 1))
);
INSERT INTO policy_control (singleton, kill_switch) VALUES (1, 0);
CREATE TABLE audit_events (
  seq INTEGER PRIMARY KEY,
  type TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  envelope TEXT NOT NULL
);
CREATE INDEX cards_conversation_status ON cards (conversation_id, status, id);
CREATE INDEX approvals_due ON approvals (conversation_id, status, json_extract(record, '$.expiresAt'));
CREATE INDEX approvals_task_pending ON approvals (json_extract(record, '$.taskId'), status);
CREATE INDEX chat_turns_task ON chat_turns (json_extract(record, '$.taskId'));
CREATE TABLE conversation_exposure (
  conversation_id TEXT PRIMARY KEY,
  untrusted INTEGER NOT NULL CHECK (untrusted IN (0, 1)),
  private_data INTEGER NOT NULL CHECK (private_data IN (0, 1))
);
