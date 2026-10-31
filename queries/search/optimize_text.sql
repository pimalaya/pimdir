-- Merges every segment of the two full-text tables into one, dropping the
-- tokens deleted rows left in them, so an erased body or summary leaves none
-- in index.db once a checkpoint truncates its WAL (§4, STORAGE §11.5). It
-- rewrites both tables whole: run it to erase, not after every pass.
INSERT INTO object_text(object_text) VALUES ('optimize');
INSERT INTO summary_text(summary_text) VALUES ('optimize');
