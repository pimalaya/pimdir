-- :attachment is 1 when the extraction wrote any text into the attachment
-- field (§6), else 0.
INSERT INTO object(hash, status, attachment) VALUES(:hash, :status, :attachment) RETURNING id;
