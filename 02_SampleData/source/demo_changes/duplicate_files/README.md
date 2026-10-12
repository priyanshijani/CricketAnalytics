# duplicate_files

An exact, byte-for-byte copy of a file already in the baseline dataset. Staging it should be detected by
content hash and skipped — no change to the warehouse, a logged "duplicate" entry in `Audit_FileControl`.
