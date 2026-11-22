-- Pi owns child transcripts, task state and replay. This is only a content-free ownership index.
CREATE TABLE runtime_subagents (
  task_id TEXT PRIMARY KEY REFERENCES tasks(id),
  conversation_id TEXT NOT NULL REFERENCES chats(id),
  original_task_id TEXT NOT NULL REFERENCES tasks(id),
  pi_owner_task_id INTEGER NOT NULL CHECK (pi_owner_task_id > 0),
  pi_conversation_id INTEGER NOT NULL CHECK (pi_conversation_id > 0),
  record BLOB NOT NULL,
  UNIQUE (conversation_id, pi_owner_task_id),
  UNIQUE (conversation_id, pi_conversation_id)
);
CREATE INDEX runtime_subagents_original ON runtime_subagents(original_task_id);
