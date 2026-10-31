# Pimdir overview

Status: informative

What the pimdir standard is and how its pieces fit, for a first-time reader. This document states no requirement: it names no table, column or statement, uses no RFC 2119 word, and where it and a part disagree the part wins. Each section ends with the part that binds.

The standard is a base and two layers:

- [STORAGE.md](./STORAGE.md): the store on disk, which every implementation provides.
- [SYNC.md](./SYNC.md): how sources reconcile through it.
- [SEARCH.md](./SEARCH.md): the index and query language over it.

Either layer can be left out, and neither works without the store. [GUIDE.md](./GUIDE.md) turns their rules into procedures for an implementer.

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

A store is a directory holding one SQLite database and one directory of bodies. The database is the index and the mutable state: which collections exist, which items they hold, their flags, and what each source last agreed to. The bodies are the content itself (a message, a card, a calendar object), each stored once in a file named by the hash of its bytes.

A body is never edited. An edit writes a new body and the item points at it; the old body stays until nothing points at it and a collector removes it.

That makes a body a fact: what each source holds can be fetched again from the remotes and the bodies rebuilt from them. The database also holds what no remote does: local edits not yet pushed, the queued actions, the links a person made between items, and the collections no source syncs. So it is never thrown away to be rebuilt without the user agreeing to lose them.

The search index is a third file beside the two, derived from both, and dropping it loses nothing.

A store carries the version of its schema. A newer implementation upgrades an older store in place and keeps everything in it. An older one refuses a newer store rather than guess at it, and no implementation rebuilds a store it cannot read.

The standard ships one way of writing the database, its canonical schema and statements, on a recent SQLite. An implementation bound to an older SQLite, a phone's own, may write the same model its own way; the store names which way it was written, a program refuses one it does not speak, and the shared test vectors hold both to the same outcomes.

Sync and search need the store. A sync needs, per source, what that source last agreed to, else a delete on one side and an add on the other look the same; the bindings hold that base. A search needs one index with one meaning of a match, which only the store's summaries, addresses and bodies give.

What is optional is the bodies: a store can hold bases and summaries alone and still sync flags and list items.

Normative: STORAGE §1, §3, §4.2, §5, §6.

## 2. The model

Six kinds of thing live in the database.

A **collection** is a mailbox, an address book, a calendar or a folder of files. It declares the media type of everything it holds, one of the four kinds the standard names, so a store never guesses what an item is. A server's collection of another type is recorded and left unsynced; a fifth kind arrives only as a change to the standard.

A collection may belong to an account, which groups collections for reading and changes the meaning of nothing else. It also keeps what its server says about it: a name to show, and a role when the server states one (the inbox or the sent folder of a mail account, the default calendar or address book of the others).

An **item** is one message, contact, event, task, journal or file, keyed within its collection by its link id. It carries the mutable state a source can change (flags), a pointer to its current body, a detail level saying how much of it has been fetched, and its position in the collection's natural order (a date for a message, a name for a card).

An **object** is one body, by hash. Two items with identical bytes share one object, so a message filed in two mailboxes costs one copy, and copying or moving an item never copies bytes. Objects are reference counted and collected as §1 says.

A **summary** is what a reader lists an item from without opening its body: subject, sender and date for a message, a name for a card, a start for an event. There is one summary table per kind, derived by whoever writes the item, never by the store. Beside it, one **address** table across every kind records who an item names and in which role, so "everything about this person" is one question.

A **binding** is one source's view of one item: the handle the source knows it by and the base, what the source last agreed to. An item with one binding is the single-source case, and adding sources adds bindings and nothing else.

A **reference** links one item to another of any kind: a message to the contact who sent it, an invitation to its event, anything a person links by hand. It names each end by its identity rather than by a collection, so it survives a move and holds while any copy of either end remains, tombstoned or retained included.

A reference is recorded once and never recomputed, by a person or by an owner's rule: a message to the card of its sender, to the event it invites to, to its attachments; a task to its project and to the message it was made from. Nothing requires one. An item with no identity of its own (a message without a Message-ID, a card without a UID) takes none, since another may share its key.

An attachment is a file standing for a part of its message. It is recorded when the message's body enters the store, holds no bytes of its own until it is saved to a folder, and goes once no reference names it.

Nothing enters the store unnamed: a source lists each member with its identity and summary, so a listed message is an item from the moment its page lands, its body fetched later or never.

A **task** carries its organisation in standard properties every client reads, nothing of the store's own. Its status, priority, categories, parent, the mail it came from and when it was captured are summary columns, and the person it waits on is one of the people it names, so a to-do created by any client takes part in every view a search can ask for.

Normative: STORAGE §2, §4.3, §14.2, Annex A.

## 3. Four identifiers

The **handle** is the source's id for an item in a collection: an IMAP UID, a DAV resource name. It belongs to one source and can be renumbered, so it never identifies an item across collections or sources.

The **link id** is the item's key in its collection, taken from what the content declares about itself: a Message-ID, a vCard or iCalendar UID. It is the same in every collection and on every source, which is how the store knows that a message in the inbox and the same message in the archive are one item.

Content that declares nothing gets a derived key, which asserts no identity: two such items are never assumed equal. A collection holding one identity twice (a double delivery, or a server that let two resources share a UID) keeps both: the second copy gets a minted key and the store judges neither.

The **hash** is the content. It is the deduplication key and the body's file name.

The **seq** is the public id: a small integer, the same wherever the item is filed, that a client shows and accepts in place of the link id. It is assigned once and never reused, so a stale id never addresses a different item.

Normative: STORAGE §9.

## 4. Roles

An **owner** is the one process that mutates the store. There is at most one at a time. It holds an advisory lock for as long as it owns the store, and everything that changes an item, a binding or a body goes through it.

A **reader** opens the database read-only and sees a consistent snapshot while the owner works. Any number may run at once. A reader shows live items only, lists from the summaries, and treats a body that is not there yet as not fetched rather than as an error.

A **producer** wants a change but does not own the store. It appends an action to the queue and the owner applies it later.

An **indexer** is a reader that writes the search index, and a **query client** reads the index with the store attached.

Normative: STORAGE §8, §14.1, §15; SEARCH §3.

## 5. Sync

The store is an offline replica of each source. For every item and every source, the binding remembers the base: the flags and the body that source last agreed to. A sync compares three things per item (the local state, the base, and what the source reports now) and derives what each side owes the other.

Flags merge element-wise and never conflict: a flag added on one side and untouched on the other is added. Bodies matter only for mutable kinds, contacts and calendar objects. A body changed locally is pushed, one changed remotely is pulled, and both changed is a conflict, settled by the source's policy or left for a person with the diverging body kept beside the item.

A push is confirmed before local state moves: an accepted push moves the base, a rejected one leaves the change pending for the next run. The source's checkpoint is recorded only after the last push of a run, so an interrupted run resumes rather than forgets.

A source lists a collection in one of two ways: the changes since its checkpoint, or a whole listing, a **round**. A round may come in pages, newest first, each page named and committed as it lands, so a large mailbox shows its newest mail within seconds and an interrupted round resumes where it stopped.

While a round is still filling, a run first lists its **head**, what changed since the round began, so a message arriving during a long first sync shows within a run rather than when the round ends.

A mail collection may be synced under a **scope**: a window on each message's own date, the one every copy and every provider agrees on. Older mail is not listed. A message missing from a round counts as deleted only when all of these hold:

- it is inside the window;
- the round has listed everything;
- the deletion would not remove most of a large mailbox at once (such a round is held open until the user confirms).

What a source says it removed is removed whatever its date, and what the user changed is pushed whatever its date. A sync deletes on a server only what the user deleted or another server removed.

Each source records its **coverage**, the window its last round covered and when, so a reader can say "mail since" and a search knows where it stops being exhaustive.

An engine speaks five verbs:

- **Open** reads the store's view of a source with no network.
- **Sync** reconciles a collection against what the source enumerates.
- **Upgrade** raises listed items to their full body (a listing is cheap, bodies hydrate on demand) and revisits an item whose summary is missing.
- **Mutate** stages a local edit offline through the same write a sync uses.
- **Rekey** rebuilds a collection whose source renumbered every handle, carrying each item's state across by link id.

A connector knows nothing of the store and answers three requests:

- list what the collection holds, page by page, each member with its identity and summary;
- fetch a batch of handles at a tier;
- push a batch of changes and report each outcome.

What it does over IMAP, JMAP or DAV is its own business.

Normative: SYNC §3 to §8.

## 6. Several sources

One item, one binding per source, and no merge between sources. A change that one source folded into the item reads, against every other source's base, as a local change, so each source's next sync pushes it. Propagation is that and nothing more.

For that to be honest, a binding keeps two agreement points:

- what the source last agreed with its own remote, from which a pending push is measured;
- what it last agreed with the shared item, from which a divergence between sources is measured.

Measuring both from one point would make a source's own unpushed edit look like another source's disagreement. The second point is also the common ancestor a merge reads, so the store keeps that body for as long as a binding names it. A pull that brings no body agrees to nothing and leaves it in place.

A divergence between sources is settled by the collection's policy: keep the incoming body, keep the existing one, or flag the item with the diverging body kept and every source's push held until a person decides. A policy that picks one body keeps the other in the trash rather than losing it. A divergence with a body nobody has read yet is always left for a person.

A divergence between a source and its own remote belongs to that binding alone. The two are recorded separately and neither implies the other.

Deletes propagate the same way. A removal on one source, stated or found by a complete listing, marks the item deleted, every other source sees a delete to push, and when the last binding is gone the item is retained.

Normative: SYNC §9; STORAGE §10.

## 7. Retention

Removal from every source is not removal from the store. When an item's last binding goes, the row and its body are kept, hidden from sync and from the live reads, and listed in a trash view. Only an explicit purge deletes the row; the body then falls to the collector. An identity that comes back revives the retained row, keeping its public id and body, so a restore costs no network.

Mail older than a sync's window is not removed either. It stays stored and readable until the owner, on the user's request, collects what lies below a date, which frees the space and tells no server anything. Widening the window later lists it again.

The owner may instead release the bodies below a date and keep the headers: the mail stays listed and searchable, and a message opened later is fetched again. A message whose body is still needed (a conflict, an unsent message, a copy owed to another source) keeps it.

Retention has no switch. How long to keep and when to purge is the owner's schedule, and a policy of purging immediately reproduces a store that never retained.

A move is not a loss: when the item's identity is held live in another collection of the account with the same body, the source row is purged at once rather than kept in the trash beside its new home. The trash also shows a deletion a source may not carry out yet, so nothing the user deleted is invisible while it waits.

Normative: STORAGE §11.

## 8. The queue

A process that does not own the store still originates changes: a client filing a message, a submission daemon, a search client tagging a hit. It appends an action to the queue: a kind, a versioned JSON payload addressing items by public id, and the body the action needs, written to the blob directory first so it is pinned.

The owner applies actions in append order, each in one transaction with the deletion of its row, so application is exactly once.

Six kinds are defined: add, set flags, remove, move, copy, update. The kind is an open string, so an application carries intents of its own, a mail submission being the worked example. An owner that does not recognise a kind, or lacks the means to perform it, skips the row and leaves it for the process that can.

A reader may overlay pending actions on what it shows, so a queued change appears before it is applied. A producer keeps the number of the row it appended and asks later whether it still waits, failed, or was applied, and for an addition which item it became, without matching the body against the store.

An addition may supersede another item, a task filed into another list. The owner applies it with the removal of the other in one step, and no server is told of that removal until the addition has reached its own, so a creation a server refuses never costs the original.

Sources do not all push the same things: one server moves messages and another cannot, one calendar sends invitation replies and another does not, one holds tasks and another refuses them. The owner declares what each source supports, from a vocabulary the standard fixes. A producer reads it before appending, so the user learns of a gap when acting rather than from a failed sync.

A verb such as sending a message, replying to an invitation or creating a folder on the server is performed by one source. When an account has several that could, the user chooses which.

Normative: STORAGE §15.

## 9. The change feed

Every item and collection carries a stamp drawn from one counter that only increases, taken when the row last changed in a way a reader can see, and no two rows share one. A consumer that derives anything from the store (the search index, a window listing a mailbox) remembers the last stamp drawn when it last looked and asks for what moved above it.

A deleted row cannot carry a stamp, so purged items and collected bodies are counted separately, and a consumer reconciles its keys only when that count moved.

Normative: STORAGE §4.5.

## 10. Search

A summary holds what a list row shows and sorts by; the index answers what the store cannot: text, calendar time across a recurring series, mail threads, and what a card holds. An indexer folds the change feed and:

- extracts each new body once, by hash, into a handful of fields (title, people, body, attachment, place, organisation, note), and indexes a bodiless item from its summary instead;
- expands every calendar item's occurrences within a rolling horizon;
- records whether a card holds a phone, a postal address, a birthday or a photo, and its categories;
- links messages into threads by their reply headers.

Text is folded (case and accents) before any full-text engine sees it, so engines that tokenise alike find the same words.

Long texts are cut into chunks along their paragraphs as they are extracted; snippets are drawn from the chunks, and an embedding index can reuse them. Occurrences are expanded again when the time zone database they were resolved through changes version, since a zoned time moves with it.

An owner keeping an index is expected to refresh it after each write it commits, so a list reading its rows from the store and its filters from the index sees them one write apart at most, and an agenda lists a window's occurrences in time order straight from the index. A refresh may stop between batches and resume where it stopped. The index remembers apart how far its last complete refresh reached, so a collection renamed while a refresh was cut short is still reconciled by the next one. An index an earlier draft built is told by its shape and rebuilt, which loses nothing.

A query is a list of terms, free text or field and value, joined by and, or and not, under a formal grammar. A query the grammar does not accept, an unknown field included, is refused whole rather than guessed at. The refusal gives the position at fault, what was expected there and the fields that exist, so a person or an agent can correct it.

Structured terms compile to seeks on the store, text terms to matches on the index, and the answer is their intersection in the store's own order. A hit is one item per account with every placement it has. The answer states its coverage:

- how many items in scope have no body to search;
- whether the date range left the horizon;
- how far the index lags the store.

Normative: SEARCH.

## 11. What binds an implementation

The three parts bind, with the canonical schema under migrations/, the statements under queries/ and the vectors under vectors/: STORAGE by the profile an implementation meets (reader, producer or owner), SYNC and SEARCH in full when offered.

Most implementations are readers or producers; the owner, the engine and the index are what io-pimdir, the reference implementation, is for. The vectors exist because the values that matter most fail silently: two implementations naming a body differently never error, they only stop sharing bodies. [GUIDE.md](./GUIDE.md) §1 lists what each profile owes and in what order to build.

A statement under queries/ binds by its name, its parameters and the columns it answers; its text is the reference an implementation may replace with its own. Each part has a version of its own, and an implementation states which version of each it conforms to. The store's major version is its schema version, so a store written under one major is read by every implementation of that major.
