-- The producer's half of §5's invariant: the action row about to name this
-- body is a pointer, counted in the enqueue transaction like every other.
-- Without it the body sits at refcount zero behind a foreign key, and the
-- collector's delete fails on the queue row rather than sparing it.
UPDATE objects SET refcount = refcount + 1 WHERE hash = :hash;
