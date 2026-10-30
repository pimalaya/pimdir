-- Clears a shared body naming no object row, before a reconciliation rebuilds
-- bindings under the foreign key an earlier draft's shape lacked (§6): that
-- draft pinned no shared body, so the collector may have swept it. The
-- binding then reads as never having folded, its cross-source comparison
-- falling back to its sync base (SYNC.md §9), which at worst reads the
-- source's own pending edit as another's: a conflict, never a lost body.
UPDATE bindings SET shared_object = NULL
WHERE shared_object IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM objects o WHERE o.hash = bindings.shared_object);
