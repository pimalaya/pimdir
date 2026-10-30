-- :attachment is 1 when the extraction wrote any text into the attachment
-- field (§6), else 0; :tel, :adr, :bday and :photo are 1 when a card holds
-- such a property, else 0, and 0 for any other kind.
INSERT INTO object(hash, status, attachment, tel, adr, bday, photo)
VALUES(:hash, :status, :attachment, :tel, :adr, :bday, :photo) RETURNING id;
