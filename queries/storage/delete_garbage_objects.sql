-- The blob files go after the commit, so a crash leaves at worst an orphan and
-- never a row without a body.
DELETE FROM objects WHERE refcount <= 0;
