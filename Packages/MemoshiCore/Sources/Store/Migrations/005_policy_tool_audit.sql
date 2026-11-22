-- These receipts identify committed runtime calls; they do not prove external effects.
CREATE TABLE policy_tool_calls (
  conversation_id TEXT NOT NULL,
  runtime_task_key TEXT NOT NULL CHECK (length(runtime_task_key) > 0),
  task_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  tool_call_id TEXT NOT NULL CHECK (length(tool_call_id) > 0),
  parent_tool_call_id TEXT,
  tool TEXT NOT NULL CHECK (length(tool) > 0),
  origin TEXT NOT NULL,
  decision_observed INTEGER NOT NULL DEFAULT 0 CHECK (decision_observed IN (0, 1)),
  preparation TEXT,
  completion_input TEXT,
  completion_seq INTEGER UNIQUE REFERENCES audit_events(seq),
  PRIMARY KEY (conversation_id, runtime_task_key),
  FOREIGN KEY (task_id, conversation_id, bot_id) REFERENCES tasks (id, conversation_id, bot_id),
  CHECK ((completion_input IS NULL AND completion_seq IS NULL) OR
         (completion_input IS NOT NULL AND completion_seq IS NOT NULL))
);

-- Only facts already present at migration may be adopted without adding a new completion.
-- Their old hook timing is not retroactively represented as proof of a Pi commit.
INSERT INTO meta (key, value)
  VALUES ('policy_tool_legacy_cutoff',
    CAST(COALESCE((SELECT seq FROM sqlite_sequence WHERE name = 'events'), 0) AS TEXT));
CREATE INDEX audit_tool_identity ON audit_events (
  type, json_extract(envelope, '$.scope.conversationId'),
  json_extract(envelope, '$.scope.taskId'), json_extract(envelope, '$.payload.toolCallId'), seq
);
CREATE INDEX chat_turns_pi_user_entry ON chat_turns (
  conversation_id, json_extract(record, '$.userEntryId')
) WHERE json_extract(record, '$.userEntryId') IS NOT NULL;
