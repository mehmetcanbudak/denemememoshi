-- Bots (object-model.md §4.3, development subset) and conversations of three kinds: the one
-- Assistant Chat, one Chat per other bot, and Sessions (§4.6), each with its own Pi store
-- (D74). Profiles render into every model request (D7); transcripts stay in Pi.
--
-- `chats` is rebuilt under its own name, keeping every row and the foreign keys of 003, 007
-- and 008. Dropping it defers each referencing row's check to commit; reinserting the same
-- IDs satisfies those checks again, and the migration's foreign_key_check confirms it.
PRAGMA defer_foreign_keys = ON;
CREATE TABLE bots (
  id TEXT PRIMARY KEY,
  role TEXT NOT NULL CHECK (role IN ('assistant', 'bot')),
  name TEXT NOT NULL CHECK (length(name) > 0),
  -- The case-folded name; names are unique ignoring case.
  name_key TEXT NOT NULL UNIQUE CHECK (length(name_key) > 0),
  job TEXT NOT NULL,
  persona TEXT NOT NULL,
  model_ref TEXT NOT NULL CHECK (length(model_ref) > 0),
  effort TEXT CHECK (effort IN ('off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')),
  revision INTEGER NOT NULL CHECK (revision > 0),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL CHECK (updated_at >= created_at)
);
CREATE UNIQUE INDEX bots_one_assistant ON bots (role) WHERE role = 'assistant';
CREATE TEMP TABLE chats_previous AS SELECT id, bot_id, record FROM chats;
-- Every 003 row is the Assistant's Chat (`assistant = 1`); its title was the Assistant's name.
INSERT INTO bots (
  id, role, name, name_key, job, persona, model_ref, effort, revision, created_at, updated_at
)
SELECT bot_id, 'assistant', json_extract(record, '$.title'),
  lower(json_extract(record, '$.title')), '', '', 'default', NULL, 1,
  json_extract(record, '$.createdAt'), json_extract(record, '$.createdAt')
FROM chats_previous;
DROP TABLE chats;
CREATE TABLE chats (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('assistant', 'bot', 'session')),
  bot_id TEXT NOT NULL REFERENCES bots (id),
  -- A Session's title; a Chat shows its bot's current name instead.
  title TEXT,
  created_at INTEGER NOT NULL,
  CHECK ((kind = 'session') = (substr(id, 1, 4) = 'ses_')),
  CHECK ((kind = 'session') = (title IS NOT NULL))
);
CREATE UNIQUE INDEX chats_one_assistant ON chats (kind) WHERE kind = 'assistant';
CREATE UNIQUE INDEX chats_one_per_bot ON chats (bot_id) WHERE kind != 'session';
CREATE INDEX chats_bot ON chats (bot_id, id);
INSERT INTO chats (id, kind, bot_id, title, created_at)
SELECT id, 'assistant', bot_id, NULL, json_extract(record, '$.createdAt') FROM chats_previous;
DROP TABLE chats_previous;
