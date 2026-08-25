---
cairn: log
change: duplicate-link-id-freeze
date: 2026-08-25
---

# The format records an identity a source holds twice

A binding pins one `handle`, so a source holding one link id twice (a double delivery, a retried append, a restore, a migration from another provider) had nowhere to put the second copy. The format said nothing about it, and the reference implementation did the only thing an unstated rule allows: it repointed the binding to the incoming handle, destroying the fact at that write, before any layer above could act on it. Reproduced against two IMAP servers, the consequence was a delete propagating from the copy the engine happened to have bound and removing the only copy on a source the user never touched.

## What moved

- **§10 gains the identity axis** beside the two content divergences it already kept apart. `bindings.ambiguous_handles` records the other handles one source holds an item's identity under, a store MUST NOT repoint an existing binding's `handle`, and a sync layer reading a binding that carries any derives nothing for that item until the source reports the identity once again. The reason is stated where the rule is: the alternative is guessing which copy a delete or a flag change refers to, and guessing wrongly destroys mail on every source that holds it.

  Recording it rather than inferring it is load-bearing, and the section says why: the second copy appears in exactly one enumeration, and an incremental one never mentions it again, so a freeze that is not persisted forgets on the next run.

  The section also states what the format does *not* do: two copies of one message is redundancy, not corruption. RFC 5322 §3.6.4 binds the generator of a `Message-ID` and says nothing about what a store may hold, so the store records the fact and judges nothing.

- **§13 gains the column's encoding**: a JSON array, or `NULL` for the ordinary case. The empty array is not written, `NULL` being "the source holds it once"; and a column an implementation cannot decode reads as `NULL`, on the same terms as a flag set, since it is not evidence of a duplicate and freezing an item on an unreadable column would strand it.

- **§4.3** names the column in the `bindings` description, and the schema carries it.

- **`update_binding` becomes a canonical statement** (queries/bindings.sql), stated rather than left implicit, and it does not carry `handle`. Rebinding legitimately, after a handle-space change (§12), goes through the rebuild that drops the old spine and inserts the new one, never through an in-place update.

## Not settled here

A binding still holds one handle per source. Letting it hold a *set*, an item deleted on a source only once every one of them vanishes, is the faithful model and a larger change: it is the natural successor to this one, and it is what a backup needs, since a frozen item is mirrored zero times rather than once. This change does not pretend to serve that case.

## Verification

io-replica implements the detection and the derive-nothing rules; io-pimdir persists the column, refuses the repoint and reports ambiguous bindings from `pimdir check`. Its spec-fidelity suite compares the inlined DDL against migrations/0001_init.sql through SQLite's own pragmas and every canonical statement name against its constants, so the column and the statement change are checked against this format on both axes. 81 tests green there, 187 in io-replica.
