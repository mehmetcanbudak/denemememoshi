-- Application projections only. Transcripts remain exclusively in Pi's conversation files.
CREATE TABLE chats (
  id TEXT PRIMARY KEY,
  bot_id TEXT NOT NULL UNIQUE,
  assistant INTEGER NOT NULL UNIQUE CHECK (assistant = 1),
  record TEXT NOT NULL
);
CREATE TABLE model_providers (
  id TEXT PRIMARY KEY,
  record TEXT NOT NULL
);
CREATE TABLE requests (
  request_id TEXT PRIMARY KEY,
  method TEXT NOT NULL,
  params_hash TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE chat_turns (
  request_id TEXT PRIMARY KEY REFERENCES requests (request_id),
  conversation_id TEXT NOT NULL REFERENCES chats (id),
  status TEXT NOT NULL,
  record TEXT NOT NULL
);
CREATE UNIQUE INDEX chat_turns_one_active ON chat_turns (conversation_id)
  WHERE status IN ('queued', 'running', 'waiting');
CREATE INDEX chat_turns_conversation ON chat_turns (conversation_id, request_id);
CREATE TABLE message_indexes (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES chats (id),
  pi_entry_id INTEGER,
  record TEXT NOT NULL,
  UNIQUE (conversation_id, pi_entry_id)
);
CREATE INDEX messages_conversation ON message_indexes (conversation_id, id);
