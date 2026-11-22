-- Store-local folder-source authority (D96): the existing `folder` Grant kind on this device.
-- Source identity and bookmark bytes stay in these rows; grant.* facts carry only identifiers.
-- Every change increments the revision, so references taken earlier become stale.
CREATE TABLE folder_grants (
  id TEXT PRIMARY KEY,
  bot_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  path TEXT NOT NULL CHECK (length(path) > 0),
  access TEXT NOT NULL CHECK (access IN ('read', 'write')),
  status TEXT NOT NULL CHECK (status IN ('active', 'revoked', 'expired')),
  revision INTEGER NOT NULL CHECK (revision > 0),
  source_device INTEGER NOT NULL,
  source_inode INTEGER NOT NULL,
  bookmark BLOB NOT NULL CHECK (typeof(bookmark) = 'blob' AND length(bookmark) > 0),
  expires_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (expires_at IS NULL OR expires_at > created_at)
);
-- The exact grant revisions one approval decision depended on. A grant change cancels its
-- pending dependents in the same transaction; terminal decisions keep their references.
CREATE TABLE approval_source_grants (
  approval_id TEXT NOT NULL REFERENCES approval_bindings (approval_id),
  grant_id TEXT NOT NULL REFERENCES folder_grants (id),
  revision INTEGER NOT NULL CHECK (revision > 0),
  position INTEGER NOT NULL CHECK (position >= 0),
  PRIMARY KEY (approval_id, grant_id),
  UNIQUE (approval_id, position)
);
CREATE INDEX approval_source_grants_grant ON approval_source_grants (grant_id, approval_id);
