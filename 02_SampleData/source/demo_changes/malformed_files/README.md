# malformed_files

A deliberately broken file — invalid JSON syntax, a CSV with the wrong column count, or a file missing
its match-identity field. Staging it should quarantine the file with a logged reason, and the rest of
the batch should still process normally.
