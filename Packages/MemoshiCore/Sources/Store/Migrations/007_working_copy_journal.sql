-- Local ownership and output-free effect metadata, never transcripts, contents or bookmarks.
-- These rows are not grants and do not make an interrupted copy safe to attach or retry.
CREATE TABLE working_copies (
  id TEXT PRIMARY KEY,
  chat_id TEXT NOT NULL REFERENCES chats(id),
  phase TEXT NOT NULL CHECK (phase IN ('admitting', 'active', 'interrupted', 'cleanup_required', 'closed')),
  record TEXT NOT NULL CHECK (length(record) <= 16384),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX working_copies_chat ON working_copies(chat_id, id);
CREATE TABLE working_copy_exports (
  copy_id TEXT NOT NULL REFERENCES working_copies(id) ON DELETE CASCADE,
  content_hash TEXT NOT NULL CHECK (length(content_hash) = 64),
  arguments_hash TEXT NOT NULL CHECK (length(arguments_hash) = 64),
  conversation_id TEXT NOT NULL,
  runtime_task_key TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('pending', 'applied', 'not_applied', 'unknown')),
  changes TEXT NOT NULL CHECK (length(changes) <= 65536),
  progress TEXT NOT NULL CHECK (length(progress) <= 65536),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (copy_id, content_hash),
  FOREIGN KEY (conversation_id, runtime_task_key)
    REFERENCES policy_tool_calls(conversation_id, runtime_task_key)
);
