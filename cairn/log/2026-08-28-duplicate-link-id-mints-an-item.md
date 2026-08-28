---
cairn: log
change: duplicate-link-id-mints-an-item
date: 2026-08-28
---

# The store keeps both copies of an identity a collection holds twice

`link_id` carried two jobs, the store's primary key and the protocol's stated identity. They agree until a server hands over a collection where they cannot, and then it is the key that has to give, not the data. [`duplicate-link-id-freeze`](./2026-08-25-duplicate-link-id-freeze.md), landed three days ago across three repositories, answered the same defect the other way round: it recorded the handle the second copy sat under and froze the item. **This supersedes it.**

Verified on 2026-08-28 against a Posteo calendar of 454 items. Four `UID`s were held under two resources each, one whose name carries the `@` and one whose name literally carries the three characters `%40`, so their href segments read `<uid>%40google.com.ics` and `<uid>%2540google.com.ics`. Two names, not one name spelled twice, and Thunderbird wrote both. Three of the four pairs differed only in `DTSTAMP`, `LAST-MODIFIED` and `X-MOZ-LASTACK`; the fourth was two genuinely different meetings sharing one `UID`. The second copy of each was stored **nowhere**: no row, no body, no `seq`, no listing, and no reader in a position to show what it was missing. For a format whose first promise (§1) is offline truth, that is the wrong failure.

The freeze did not even stick. §10 justified the column with "the second copy appears in exactly one enumeration, and an incremental one never mentions it again", which holds for a delta and not for a collection whose server implements no `sync-collection`: that one is listed in full by `PROPFIND` on every run, so the second copy was rediscovered every run, its body downloaded whole to resolve its identity (Annex A.3 has no cheap tier), the freeze reapplied, and the body left unreferenced. Four bodies and four orphan blobs per sync on that account, plus a report line naming work that never completed.

## What landed

- **§9 assigns the key, Annex A derives the hint.** The `link_id` is the item's key in its collection, taken from the first branch that applies: the kind's fallback when the content states no usable hint (`alt:`, `hash:`, both unchanged), the hint verbatim when it is free in that collection, and a **minted** key when an item this source binds under a different handle already carries it. The minted form is `dup:`, the hint, `#` and that handle, concatenated verbatim and nothing else. No digest, because whatever mints one depends on nothing that hashes; deterministic, so a rebuilt store mints the same key; prefixed like the fallbacks, so the rule that a prefixed id is never pushed as a protocol `UID` covers it with no new case. It is opaque: never parsed, never re-canonicalised, kept for ever even after the copy holding the bare hint is deleted, since rewriting it would change a `seq` a consumer has already shown.

- **The asymmetry is stated where it can be read.** Dedup keys on the hash, matching keys on the hint, and the key is neither. `lookup_objects` is keyed on the assigned `link_id`, so a minted item finds no body there and fetches its own: a missed dedup, which §9 already calls harmless, in preference to a wrong merge, which it calls the one that hides data.

- **§9.1: a minted key is a different item** and draws its own `seq`, `seq_for_link_any` finding none for a key nothing else holds. The copy holding the bare hint keeps the store-global one, so the cross-collection guarantee is untouched: one message filed in two mailboxes still shows once, and what shows twice is two resources one collection genuinely holds. §9.2 says the same for accounts: minting separates two resources inside one collection, never two collections that legitimately share a hint.

- **§10 loses the identity axis it gained three days ago.** `bindings.ambiguous_handles` and the frozen projection it fed are gone. The half of the rule that still holds is restated as a plain refusal: a write resolving an existing `(collection, link_id, source)` binding to a different handle SHALL be refused, and the store records no trace of the incoming handle. A source holding one identity twice never reaches that refusal, the second copy having resolved to a key of its own before the write. §12's rebuild remains the one licensed rebind, per handle, and its closing sentence now says the batch is *refused* rather than frozen.

- **§13 drops the column and states what `link_id` actually is**: the hint verbatim, a kind fallback, or a minted `dup:<hint>#<handle>`, opaque to a store that never parses one and never rewrites one. §14 says why `update_binding` carries no `handle` and cannot, and §14.1 says `list_link_placements` pairs by key rather than by hint, so the body read is what pairs a minted copy with its twin.

- **§15.3 keeps the queued `add` parking on a duplicate `link_id`, and says why the two answers differ.** Reading a source means taking the collection it actually holds, so a claimed hint is minted a key and stored; authoring locally means a producer named a key the collection already holds and got it wrong, which is worth telling it about rather than filing under a key it never asked for. Liberal in what is accepted from a source, strict in what a producer may create.

- **Annex A names each kind's hint** (the bare `Message-ID`, the vCard `UID`, the iCalendar `UID`) and says that the annex derives it while §9 assigns the key. A.3 loses the sentence it rested on, "`(collection, link_id)` is then exactly the uniqueness CalDAV itself enforces", and states the opposite: RFC 4791 §4.1 requires that uniqueness of a calendar collection, RFC 6352 §5.1 and §6.3.2 of an address book one, and the format does not assume the server enforced either. The recurrence-set rule is unchanged, one resource per `UID` on the wire being a separate fact.

- **The canonical SQL follows**, version 1 still edited in place (§6): the column leaves `bindings`, `load_bindings`, `load_bindings_by_link`, `insert_binding` and `update_binding`, and the schema now says of `handle` that it is bound once. No statement keyed on `link_id` assumed it equalled the hint; `lookup_objects` and `list_link_placements` gained the comment saying so, since both read differently now that it may not.

- **Three vectors pin the minted key**, one per kind, each reusing the fixture of the case above it because minting depends on the hint and the handle and never on the body. The handle is what a binding actually holds, which for DAV is the resource name, the href's last segment exactly as the server returned it and decoded by nobody: `dup:event-utc@example.org#event-utc%2540example.org.ics` is the observed Posteo pair written out with this repository's own `UID`, so two implementations cannot mint differently. §16 says those three cases bind where the rest of meta.json only ought to: they restate §9 rather than an Annex A convention, and two implementations minting differently file the same second copy under two keys, neither able to read the other's store.

## What deliberately did not move

No repair verb, in the format or anywhere else: deleting a duplicate or re-`UID`ing one is a decision taken against the server. No new column and no new statement, the mint decision belonging to the engine's load-by-link-ids and the store persisting the key it is handed. No hint-keyed read: `list_link_placements` still pairs by key, and a `hint_placements` statement is the natural successor rather than part of this. And the store still resolves nothing (§9.2): it picks no survivor, merges nothing, deletes nothing, warns about nothing. Two items is the report.

## Verification

This repository holds no toolchain, so the checks are the two under checks/ and the reference implementation's suites. The schema applies at version 1 and all 60 canonical statements prepare against it. The vectors re-derive: 7 base32 cases, 13 object names, 20 fixtures and the 3 new minted keys, the last through a check added to checks/vectors.py that rebuilds the key from the case's `hint` and `handle` rather than comparing a string a hand could have typed either way.

Every surviving mention of `ambiguous` in the repository was reviewed and is deliberate: the account-namespacing rule (§9.2) and the ambiguous-hour convention (§A.3) with its fixture. Every column §13 names exists in migrations/0001_init.sql, every name §14 uses resolves to a canonical statement or a column, and every statement queries/ declares is named somewhere in SPEC.md.

io-pimdir's spec-fidelity suite, the only place this format's SQL is ever loaded, reports **exactly one** difference against this checkout, and it is this change: its inlined `bindings` still carries `ambiguous_handles`. Its three statement tests pass unchanged. That drift is the third step of this change closing itself (io-replica mints, io-pimdir removes the column and keeps the refusal), and the delta is already written there.
