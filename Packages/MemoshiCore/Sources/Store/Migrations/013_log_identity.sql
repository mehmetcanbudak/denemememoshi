-- The event log's identity (D131): one random opaque value, created with the log in a new
-- store and at the first open of an older one, and never rewritten afterwards. It lives in this
-- database, so a copy of the file carries it and a newly created database mints another.
INSERT INTO meta (key, value) VALUES ('log_id', lower(hex(randomblob(16))));
