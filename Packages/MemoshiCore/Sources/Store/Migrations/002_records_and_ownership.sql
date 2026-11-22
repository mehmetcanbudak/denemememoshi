CREATE TABLE leases (
  conversation_id TEXT PRIMARY KEY,
  epoch INTEGER NOT NULL CHECK (epoch > 0),
  runner_device_id TEXT,
  expires_at INTEGER,
  CHECK ((runner_device_id IS NULL AND expires_at IS NULL) OR
         (runner_device_id IS NOT NULL AND expires_at IS NOT NULL))
);
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  parent_task_id TEXT,
  status TEXT NOT NULL,
  record TEXT NOT NULL,
  UNIQUE (id, conversation_id, bot_id),
  FOREIGN KEY (parent_task_id, conversation_id, bot_id) REFERENCES tasks (id, conversation_id, bot_id)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX tasks_parent ON tasks (parent_task_id, id);
CREATE TABLE cards (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  task_id TEXT,
  status TEXT NOT NULL,
  record TEXT NOT NULL,
  FOREIGN KEY (task_id, conversation_id, bot_id) REFERENCES tasks (id, conversation_id, bot_id)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE approvals (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  status TEXT NOT NULL,
  record TEXT NOT NULL,
  FOREIGN KEY (task_id, conversation_id, bot_id) REFERENCES tasks (id, conversation_id, bot_id)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX approvals_status ON approvals (status, id);
CREATE INDEX approvals_bot ON approvals (bot_id, id);
CREATE TABLE settings (
  key TEXT PRIMARY KEY CHECK (key = 'event_retention_days'),
  value INTEGER NOT NULL CHECK (value BETWEEN 7 AND 365)
);
INSERT INTO settings (key, value) VALUES ('event_retention_days', 30);
