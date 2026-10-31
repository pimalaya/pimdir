-- Where §7's bounds stopped a calendar item's expansion, written with its
-- occurrences: the instant from which they are not all written, or NULL when
-- neither bound stopped it.
UPDATE placement SET cut = :cut WHERE collection = :collection AND seq = :seq;
