# Pimdir overview

Status: informative

What the pimdir standard is and how its pieces fit, for a reader meeting it for the first time. This document states no requirement: it names no table, column or statement, uses no RFC 2119 word, and where it and a part disagree the part wins. Each section ends with the part that binds.

The standard itself is a base and two layers: [STORAGE.md](./STORAGE.md), the store on disk, which every implementation provides; [SYNC.md](./SYNC.md), how sources reconcile through it; [SEARCH.md](./SEARCH.md), the index and query language over it. Either layer can be left out, and neither works without the store. [GUIDE.md](./GUIDE.md) turns their rules into procedures for an implementer.

## Contents

1. [A store](#1-a-store)
2. [The model](#2-the-model)
3. [Four identifiers](#3-four-identifiers)
4. [Roles](#4-roles)
5. [Sync](#5-sync)
6. [Several sources](#6-several-sources)
7. [Retention](#7-retention)
8. [The queue](#8-the-queue)
9. [The change feed](#9-the-change-feed)
10. [Search](#10-search)
11. [What binds an implementation](#11-what-binds-an-implementation)

## 1. A store

A store is a directory holding one SQLite database and one directory of bodies. The database is the index and the mutable state: which collections exist, which items they hold, their flags, and what each source last agreed to. The bodies are the content itself, a message, a card or a calendar object, each stored once in a file named by the hash of its bytes.

A body is never edited. An edit writes a new body and the item points at it; the old body stays until nothing points at it and a collector removes it. That is what makes a body a fact and the database a derived view of the facts: apart from local edits not yet pushed, the whole database can be rebuilt from the bodies and the remotes.

The search index is a third file beside the two, derived from both, and dropping it loses nothing.

Sync and search are layers on the store, and neither stands without it. A sync between two sources needs, per source, what that source last agreed to, else a delete on one side and an add on the other are the same picture; the bindings hold that base, and the state file every two-way tool keeps beside its folders is a store in miniature. A search needs one index with one meaning of a match, which only the store's summaries, addresses and bodies give; a query fanned out to each source's own search answers as slowly as the slowest, offline never, and with no two sources agreeing on what "contains" means. What is optional is the bodies: a store can hold bases and summaries alone and still sync flags and list items.

Normative: STORAGE §1, §3, §5, §6.

## 2. The model

Five kinds of thing live in the database.

A **collection** is a mailbox, an address book or a calendar. It declares the media type of everything it holds, so a store never guesses what an item is, and it may belong to an account, which groups collections for reading and changes the meaning of nothing else.

An **item** is one message, contact, event, task or journal, keyed within its collection by its link id. It carries the mutable state a source can change (flags), a pointer to its current body, a detail level saying how much of it has been fetched, and its position in the collection's natural order (a date for a message, a name for a card).

An **object** is one body, by hash. Two items with identical bytes share one object, so a message filed in two mailboxes costs one copy, and copying or moving an item never copies bytes. Objects are reference counted, and an object nothing points at stays on disk until a collector runs.

A **summary** is what a reader lists an item from without opening its body: subject, sender and date for a message, a name for a card, a start for an event. One summary table per kind, derived by whoever writes the item, never by the store. Beside it, one **address** table across every kind records who an item names and in which role, so "everything about this person" is one question.

A **binding** is one source's view of one item: the handle the source knows it by and the base, what the source last agreed to. An item with one binding is the single-source case, and adding sources adds bindings and nothing else.

A handle a source has listed but not yet identified is a **probe**, held as a row until the fetch that names it.

Normative: STORAGE §2, §4.3, Annex A.

## 3. Four identifiers

The **handle** is the source's id for an item in a collection: an IMAP UID, a DAV resource name. It belongs to one source and can be renumbered, so it never identifies an item across collections or sources.

The **link id** is the item's key in its collection, taken from what the content declares about itself: a Message-ID, a vCard or iCalendar UID. It is the same in every collection and on every source, which is how the store knows that a message in the inbox and the same message in the archive are one item. Content that declares nothing gets a derived key, and a derived key asserts no identity: two such items are never assumed equal. A collection holding one identity twice, through a double delivery or a server that let two resources share a UID, keeps both: the second copy gets a minted key and the store judges neither.

The **hash** is the content. It is the deduplication key and the body's file name.

The **seq** is the public id: a small integer, the same wherever the item is filed, that a client shows and accepts in place of the link id. It is assigned once and never reused, so a stale id never addresses a different item.

Normative: STORAGE §9.

## 4. Roles

An **owner** is the one process that mutates the store. There is at most one at a time, it holds an advisory lock for as long as it owns the store, and everything that changes an item, a binding or a body goes through it.

A **reader** opens the database read-only and sees a consistent snapshot while the owner works. Any number may run at once. A reader shows live items only, lists from the summaries, and treats a body that is not there yet as not fetched rather than as an error.

A **producer** wants a change but does not own the store. It appends an action to the queue and the owner applies it later.

An **indexer** is a reader that writes the search index, and a **query client** reads the index with the store attached.

Normative: STORAGE §8, §14.1, §15; SEARCH §3.

## 5. Sync

The store is an offline replica of each source. For every item and every source, the binding remembers the base: the flags and the body that source last agreed to. A sync compares three things per item, the local state, the base and what the source reports now, and derives what each side owes the other.

Flags merge element-wise and never conflict: a flag added on one side and untouched on the other is added. Bodies matter only for mutable kinds, contacts and calendar objects. A body changed locally is pushed, a body changed remotely is pulled, and both changed is a conflict, settled by the source's policy or left for a person with the diverging body kept beside the item.

A push is confirmed before local state moves: an accepted push moves the base, a rejected one leaves the change pending for the next run. The source's checkpoint is recorded only after the last push of a run, so an interrupted run resumes rather than forgets.

An engine speaks five verbs. **Open** reads the store's view of a source with no network. **Sync** reconciles a collection against what the source enumerates. **Upgrade** raises items up the detail ladder, from a listed handle to identity and summary to a full body, since enumeration is cheap and bodies hydrate on demand. **Mutate** stages a local edit offline through the same write a sync uses. **Rekey** rebuilds a collection whose source renumbered every handle, carrying each item's state across by link id.

A connector answers three requests and knows nothing of the store: enumerate what the collection holds, fetch a batch of handles at a tier, push a batch of changes and report each outcome. What it does over IMAP, JMAP or DAV is its own business.

Normative: SYNC §3 to §8.

## 6. Several sources

One item, one binding per source, and no merge between sources. A change that one source folded into the item reads, against every other source's base, as a local change, so each source's next sync pushes it. Propagation is that and nothing more.

For that to be honest a binding keeps two agreement points: what the source last agreed with its own remote, which is what a pending push is measured from, and what it last agreed with the shared item, which is what a divergence between sources is measured from. Measuring both from one point would make a source's own unpushed edit look like another source's disagreement.

A divergence between sources is settled by the collection's policy: keep the incoming body, keep the existing one, or flag the item with the diverging body kept and every source's push held until a person decides. A divergence between a source and its own remote belongs to that binding alone. The two are recorded separately and neither implies the other.

Deletes propagate the same way. A removal on one source marks the item deleted, every other source sees a delete to push, and when the last binding is gone the item is retained.

Normative: SYNC §9; STORAGE §10.

## 7. Retention

Removal from every source is not removal from the store. When an item's last binding goes, the row and its body are kept, hidden from sync and from the live reads, and listed in a trash view. Only an explicit purge deletes the row; the body then falls to the collector. An identity that comes back revives the retained row, keeping its public id and body, so a restore costs no network.

Retention has no switch. How long to keep and when to purge is the owner's schedule, and a policy of purging immediately reproduces a store that never retained. A move is not a loss: when the item's identity is held live in another collection of the account with the same body, the source row is purged at once rather than kept in the trash beside its new home. The trash also shows a deletion a source may not carry out yet, so nothing the user deleted is invisible while it waits.

Normative: STORAGE §11.

## 8. The queue

A process that does not own the store still originates changes: a client filing a message, a submission daemon, a search client tagging a hit. It appends an action to the queue: a kind, a versioned JSON payload addressing items by public id, and the body the action needs, written to the blob directory first so it is pinned. The owner applies actions in append order, each in one transaction with the deletion of its row, so application is exactly once.

Six kinds are defined: add, set flags, remove, move, copy, update. The kind is an open string, so an application carries intents of its own, a mail submission being the worked example, and an owner that does not recognise a kind, or lacks the means to perform it, skips the row and leaves it for the process that can. A reader may overlay pending actions on what it shows, so a queued change appears before it is applied.

Normative: STORAGE §15.

## 9. The change feed

Every item and collection carries a stamp drawn from one counter that only increases, taken when the row last changed in a way a reader can see, and no two rows share one. A consumer that derives anything from the store, the search index or a window listing a mailbox, remembers the last stamp drawn when it last looked and asks for what moved above it. A deleted row cannot carry a stamp, so purged items and collected bodies are counted separately and a consumer reconciles its keys only when that count moved.

Normative: STORAGE §4.5.

## 10. Search

The index answers what the store cannot: text, calendar time across a recurring series, and mail threads. An indexer folds the change feed, extracts each new body once by hash into a handful of fields (title, people, body, attachment, place, organisation, note), indexes a bodiless item from its summary instead, expands every calendar item's occurrences within a rolling horizon, and links messages into threads by their reply headers.

A query is a list of terms, free text or field and value, joined by and, or and not. Structured terms compile to seeks on the store, text terms to matches on the index, and the answer is their intersection in the store's own order. A hit is one item per account with every placement it has, and the answer states its coverage: how many items in scope have no body to search, and whether the date range left the horizon.

Normative: SEARCH.

## 11. What binds an implementation

The three parts, with the canonical schema under migrations/, the statements under queries/ and the vectors under vectors/: STORAGE by the profile an implementation meets, reader, producer or owner; SYNC and SEARCH in full when offered. Most implementations are readers or producers; the owner, the engine and the index are what io-pimdir, the reference implementation, is for. The vectors exist because the values that matter most fail silently: two implementations naming a body differently never error, they only stop sharing bodies. [GUIDE.md](./GUIDE.md) §1 lists what each profile owes and in what order to build.
