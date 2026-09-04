-- A write batch dropping a placement names a handle, while the shared item is
-- keyed by link id. Rides bindings_by_handle, so it is a seek: answering it by
-- loading the collection is what makes a one-row write cost a whole-mailbox
-- read (§14).
SELECT link_id FROM bindings
WHERE collection = :collection AND source = :source AND handle = :handle;
