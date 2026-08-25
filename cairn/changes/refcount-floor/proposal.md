---
cairn: change
id: refcount-floor
status: landed
created: 2026-08-25
---

# A refcount cannot go negative unnoticed

## Why

`objects.refcount` is a plain `INTEGER NOT NULL DEFAULT 0`, maintained only as `refcount + :delta`. A double release drives it negative, and nothing says so. The sweep now tests `<= 0`, so such an object is at least collected rather than leaked for ever, but the bookkeeping error that produced it stays invisible.

The schema is `STRICT` precisely so a column means what it says, and this is the class of error that discipline exists to catch loudly. §7 lists integrity as a property the store maintains; a count that can silently go negative is one it does not.

## What

- `CHECK (refcount >= 0)` on `objects`, in the canonical schema.
- The draft reconciliation gains a table rebuild for it: `ALTER TABLE` cannot add a constraint, so an existing store is migrated by creating the constrained table, copying, dropping and renaming, inside the transaction that already reconciles columns and indexes.
- A store whose data violates it on rebuild is a store with a real drift: repair it with `recompute_refcounts` first (see `check --fix`), then constrain.

## Scope / non-goals

- Version 1 is still edited in place while the format is draft; this is a shape change, not a new version.
- No change to how counts are maintained.
