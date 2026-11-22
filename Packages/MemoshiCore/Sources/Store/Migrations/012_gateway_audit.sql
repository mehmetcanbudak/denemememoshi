-- Per-task host summaries. Individual network policy checks remain separate audit facts.
CREATE TABLE gateway_audit_hosts (
  conversation_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  computer_id TEXT NOT NULL,
  host TEXT NOT NULL,
  allowed INTEGER NOT NULL CHECK (allowed IN (0, 1)),
  pending_count INTEGER NOT NULL DEFAULT 0 CHECK (typeof(pending_count) = 'integer' AND pending_count >= 0),
  last_at INTEGER NOT NULL,
  PRIMARY KEY (task_id, computer_id, host, allowed),
  FOREIGN KEY (task_id, conversation_id, bot_id) REFERENCES tasks (id, conversation_id, bot_id) ON DELETE CASCADE
);
