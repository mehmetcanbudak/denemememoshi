-- Session Trash is local in Phase 0; bot/group lifecycle and cross-device merge stay separate.
-- A purged row remains as a content-free tombstone. Leases and original receipts also survive.
ALTER TABLE chats ADD COLUMN deleted_at INTEGER CHECK (deleted_at IS NULL OR deleted_at >= 0);
ALTER TABLE chats ADD COLUMN purge_after INTEGER CHECK (purge_after IS NULL OR purge_after >= deleted_at);
ALTER TABLE chats ADD COLUMN purge_pending INTEGER NOT NULL DEFAULT 0 CHECK (purge_pending IN (0, 1));
ALTER TABLE chats ADD COLUMN purged_at INTEGER CHECK (purged_at IS NULL OR purged_at >= deleted_at);
CREATE INDEX chats_trash ON chats (deleted_at, id) WHERE deleted_at IS NOT NULL;

-- Filesystem unlink and the application database cannot commit atomically. Freeze a purge's
-- selection before unlinking; after process death the same original request finishes that job.
CREATE TABLE session_purge_jobs (
  request_id TEXT PRIMARY KEY,
  params_hash TEXT NOT NULL,
  session_ids TEXT NOT NULL,
  actor TEXT NOT NULL CHECK (actor IN ('user', 'system')),
  created_at INTEGER NOT NULL
);
