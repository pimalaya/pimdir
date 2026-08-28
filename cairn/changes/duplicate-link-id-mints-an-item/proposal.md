---
cairn: change
id: duplicate-link-id-mints-an-item
status: landed
created: 2026-08-28
---

# A collection holds both copies of a duplicated identity

> Cross-repo change, same id in eight repositories, in this order:
> **pimdir** (here: the rule) → **io-replica** (the mint, and the removal of the freeze) → **io-pimdir** (the column goes, the refusal stays) → **io-webdav** (the refusal is named) → **neverest** (the resource name, the push guard, the report) → **himalaya**, **cardamum**, **calendula** (stop assuming a link id is unique). The format has other implementations and readers (pimalaya/android, himalaya-android-m3, linux, pimgate) which are handled outside this set.
>
> This **supersedes `duplicate-link-id-freeze`** (landed 2026-08-25, all three repositories): same defect, opposite answer. That change recorded the second copy's handle; this one stores the second copy.

## Why

Both DAV protocols require a `UID` to be unique inside its collection: RFC 4791 §4.1 for calendar object resources, RFC 6352 §5.1 and §6.3.2 for address object resources. Annex A.3 rests on it, in as many words: "`(collection, link_id)` is then exactly the uniqueness CalDAV itself enforces". Servers break it anyway.

Verified 2026-08-28 against a Posteo calendar of 454 items: four `UID`s were held under two hrefs each, one named `<uid>@google.com.ics` and one named `<uid>%40google.com.ics`, both written by Thunderbird. Three pairs differed only in `DTSTAMP`, `LAST-MODIFIED` and `X-MOZ-LASTACK`. The fourth was two genuinely different meetings sharing one `UID`.

Two consequences, both live:

- **The second copy is not in the store.** §10 records the other handle and nothing else, so the format holds one item per identity per collection: no row, no body, no `seq`, no listing. One of those four events existed on the server and nowhere in the replica, and no reader could show what it was missing. For a format whose first promise (§1) is offline truth, that is the wrong failure.
- **The freeze does not stick where enumeration is not incremental.** §10 justifies the column with "the second copy appears in exactly one enumeration, and an incremental one never mentions it again". That holds for a delta. A CalDAV or CardDAV collection whose server implements no `sync-collection` is listed in full by `PROPFIND` on every run, so the second copy is rediscovered every run, its body downloaded in full to resolve its identity (Annex A.3 has no cheap tier), the freeze reapplied, and the body left unreferenced. Measured on that account: four bodies and four orphan blobs per sync, plus a report line naming work that never completes.

Underneath both: `link_id` carries two jobs, the store's primary key and the protocol's stated identity. They agree until a server hands over a collection where they cannot, and then it is the key that has to give, not the data.

The posture this change takes is Postel's: **liberal in what the store accepts, strict in what it produces**. Two resources under one `UID` are stored as two items, because that is what the server holds. Nothing is invented on the way out: a duplicate is offered to another source under its own resource name, carrying the `UID` it actually has, and a server that refuses it with `no-uid-conflict` is reported verbatim.

## What

1. **§9: `link_id` is the store's key, not a restatement of the protocol's identity.** Its value is the **identity hint** (Annex A: the `Message-ID`, the vCard or iCalendar `UID`) verbatim when that hint is free in the collection, and a minted variant of it when it is not. Annex A keeps defining the hint; §9 defines the key.

2. **The minting rule**, applied where an item's identity resolves:
   - no usable hint: the kind's existing fallback, unchanged (`alt:` for mail, `hash:` for a DAV resource);
   - hint free in this collection: the hint, verbatim, which is every item written before this change;
   - hint already carried by an item **this source binds under a different handle**: a minted id.

3. **The minted form** is `dup:`, the hint, `#`, and the handle verbatim. No digest: the engine that mints it depends on nothing that hashes, the key is opaque and never parsed, and carrying the handle makes a duplicate traceable to the resource it came from. It is deterministic, so a rebuilt store reproduces the same key, and it is prefixed like the other minted forms, so the rule that a prefixed id is never pushed as a `UID` needs no new case.

4. **§9.1 is untouched.** One message filed in two collections keeps the bare hint in both, so it keeps one store-global `seq` and a merged view still shows it once. A minted item is a different item, separately listed and separately deletable, so it draws its own `seq`.

5. **Deduplication is unchanged and stays keyed on the hash.** Two byte-identical copies in one collection are two items sharing one object, refcounted twice. `lookup_objects` is keyed on the final `link_id`, so a minted item finds no body and fetches its own: a missed dedup, which §9 already calls harmless, in preference to a wrong merge, which it calls the one that hides data.

6. **§10: `ambiguous_handles` is removed**, along with the frozen status it fed. The rule it protected stays and gets simpler: a write that would repoint an existing `(collection, link_id, source)` to a different handle SHALL be **refused**, and the only legitimate rebind remains §12's rebuild. Nothing is recorded in its place, because the second copy now has a row of its own.

7. **The store still resolves nothing** (§"Multiplicity is reported, never resolved"). It does not choose a survivor, does not merge, does not delete, and does not warn. Two items is the report.

## Scope / non-goals

- **No repair verb**, in the format or in an implementation. Deleting a duplicate or re-`UID`ing one is the user's decision, taken against the server.
- **No re-canonicalisation.** If the copy holding the bare hint is deleted, the minted copy keeps its minted key for ever. The key is opaque, and rewriting it would change a `seq` a consumer has already shown.
- **No new column and no new statement.** The mint decision belongs to the engine and is made on the load-by-link-ids it already performs before writing a resolved batch; the store persists the key it is handed and takes no position on its shape.
- **No hint-keyed read.** `link_placements` keeps pairing by key, so it will not pair a minted item with its bare twin. A consumer wanting that pairing today reads `object_placements` (which pairs the identical case) or derives the hint from the minted key. A `hint_placements` statement is the natural successor, not part of this.
- **Version 1 stays edited in place** while the format is draft (§6), so removing the column is a shape change reconciled on open, not a new version.
