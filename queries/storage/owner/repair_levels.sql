-- Reconciliation's repair (§6): a row an earlier draft wrote at level 0, a
-- claim read as Meta, takes 1 before the rebuild the closed ladder refuses it
-- in (§13).
UPDATE items SET level = 1 WHERE level = 0;
