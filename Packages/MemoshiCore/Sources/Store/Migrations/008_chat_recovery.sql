-- Unsubmitted inputs only. Canonical transcript content remains exclusively in Pi.
CREATE TABLE chat_queued_inputs (
  request_id TEXT PRIMARY KEY REFERENCES chat_turns(request_id) ON DELETE CASCADE,
  conversation_id TEXT NOT NULL REFERENCES chats(id),
  record TEXT NOT NULL CHECK (length(CAST(record AS BLOB)) <= 262144)
);
CREATE INDEX chat_queued_inputs_conversation ON chat_queued_inputs(conversation_id, request_id);
-- Recovery-held inputs do not compete with the one actually admitted Pi turn.
DROP INDEX chat_turns_one_active;
CREATE UNIQUE INDEX chat_turns_one_active ON chat_turns(conversation_id)
  WHERE status IN ('queued', 'running', 'waiting')
    AND json_extract(record, '$.queueReason') IS NULL;
CREATE INDEX tasks_conversation_status ON tasks(conversation_id, status, id);
-- Content-free dispatch intent; a successful Pi result must be observed before retirement.
CREATE TABLE unsafe_tool_dispatches (
  conversation_id TEXT NOT NULL,
  runtime_task_key TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('started', 'returned', 'unknown')),
  expected_ok INTEGER CHECK (expected_ok IN (0, 1)),
  started_at INTEGER NOT NULL,
  CHECK ((state = 'returned' AND expected_ok IS NOT NULL)
    OR (state != 'returned' AND expected_ok IS NULL)),
  PRIMARY KEY (conversation_id, runtime_task_key),
  FOREIGN KEY (conversation_id, runtime_task_key)
    REFERENCES policy_tool_calls(conversation_id, runtime_task_key)
);
