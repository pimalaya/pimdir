# Pimdir interchange format (file-per-item export profile)

Status: draft. **This is the portable *interchange* profile, not the native store.** The native pimdir store is the SQLite + blob-files format specified in [`SPEC.md`](./SPEC.md); this document specifies a dependency-free, tool-agnostic file-per-item layout that a pimdir store can *export to* and *import from* for archival, backup and interop with `Maildir`, `m2dir`, `vdir`, `mutt`, `rsync` and the like. It is deliberately *not* meant to scale or to be queried live — those are the native store's job — so its filesystem costs (no index, per-item files, partial OS compatibility) do not apply to normal operation.

A single on-disk format for storing text-based personal-information items (mail, calendar events, contacts, notes, tasks) as plain files plus metadata. Pimdir unifies the roles that Maildir, m2dir (https://man.sr.ht/~bitfehler/m2dir/) and vdir (https://pimutils.org/specs/vdir/) play for their respective domains into one generic, portable format.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119.

## 1. Goals and lineage

Pimdir takes m2dir's store-and-collection skeleton and vdir's one-item-per-file simplicity, drops everything tied to a single domain or to a single operating system, and adds first-class Windows support as a hard requirement. Its design goals, in priority order:

- Generic: one format for any text-based item kind, identified by media type, not one format per domain.
- Portable: works unchanged on case-insensitive and network filesystems (NTFS, SMB, NFS, APFS), which Maildir, m2dir and vdir do not.
- Self-describing and self-contained: a collection directory carries its own identity, its items, and all their metadata, so it can be copied or moved anywhere and still be read by any compliant tool.
- No global derived state: there is no index, log or snapshot in the format, so there is no global structure for a careless tool to corrupt. Damage is always local to one item and is recoverable from the item itself.
- Lock-free: every mutation is an atomic rename, so uncoordinated tools never need a shared lock and never corrupt each other.

Any search index, envelope cache or sync database is a derived layer that a consumer MAY build on top of a pimdir store, rebuilt from the store at will, and is out of scope for this specification.

## 2. Terminology

- Store: the top-level directory holding the whole dataset.
- Collection: a directory under the store holding items of one kind (a mailbox, a calendar, an address book).
- Item: a single file holding exactly one message, event, task or contact.
- Uuid: a generated 128-bit identifier naming a collection or identifying an item; stable for the life of the thing it names.
- Hash: a cryptographic content hash of an item's bytes; the item's etag, integrity value and dedup key.
- Marker: a reserved dotfile that identifies the store.
- Meta: the JSON metadata document for a given uuid.

### 2.1 Identifier encoding

All identifiers that appear in a path (uuids and hashes) MUST be encoded with a single-case, filesystem-safe alphabet: lowercase base32 (RFC 4648, no padding) is RECOMMENDED. A single-case alphabet is mandatory because case-insensitive filesystems would otherwise collapse two distinct identifiers that differ only in case into one path and corrupt data. Base64 and base64url MUST NOT be used for on-disk names for this reason.

A uuid is a 128-bit value (a random UUIDv4 is RECOMMENDED), encoded as above. A hash is a content hash of at least 128 bits (a SHA-256 truncated to 128 bits, or BLAKE3, is RECOMMENDED), encoded as above.

## 3. Store layout

A store is a directory containing a marker file named `.pimstore` and zero or more collection directories. The marker is a small JSON document:

```json
{ "version": 1 }
```

A directory is a pimdir store if and only if it contains a readable `.pimstore` marker. Every entry of the store whose name does not start with a period and which is a directory is a collection. Entries beginning with a period are format machinery and MUST be ignored when enumerating collections.

Collections are stored flat, directly under the store root, and are never nested on disk. Logical hierarchy (for example an IMAP mailbox tree) is expressed by metadata, not by directory nesting (see 5.2). Flat storage keeps path lengths bounded, which matters for the classic Windows MAX_PATH limit, and avoids per-segment naming problems.

## 4. Collections

A collection is a directory whose name is a uuid. It contains a `.meta` directory (see 6) and the content files of its items. The collection is valid if and only if its `.meta` directory contains a metadata document for the collection's own uuid, that is `.meta/<collection-uuid>.json`.

All items in a collection share one media type, declared once in the collection metadata (see 5.1). This is why item files need carry no per-item type beyond a convenience extension.

## 5. Items

Each item is a single file holding exactly one item of the collection's kind. A file MUST NOT hold more than one message, event, task or contact.

### 5.1 Filename

An item filename has three dot-separated fields:

```
item-filename = uuid "." hash "." ext
```

- `uuid` is the item's stable identity. It is generated when the item is first stored and never changes for the item's life.
- `hash` is the content hash of the item's exact bytes. It is the item's etag and integrity value, and it changes whenever the content changes.
- `ext` is the conventional extension for the collection's media type (`eml` for `message/rfc822`, `ics` for `text/calendar`, `vcf` for `text/vcard`, `txt` for `text/plain`, and so on). It makes the file self-describing and tool-friendly, and MUST be consistent with the collection kind.

Because uuid and hash use an encoding that contains no period, a filename is parsed by splitting on periods into exactly three fields. Example:

```
mfsg2ylom4qgg33oeireeuqr.k4zsa3dpnvxha7l5.eml
```

### 5.2 Identity versus content

The uuid is identity; the hash is content state. They are deliberately separate, where m2dir merged them into one token. Two items with identical bytes still have distinct uuids and are therefore two distinct items (the same message delivered twice, or filed in two collections, is kept twice). Deduplication, if a store wants it, is a storage-layer optimisation keyed on equal hash (for example a hardlink) and never changes item identity.

Intrinsic identifiers carried by the content itself (a `Message-ID` header, an iCalendar or vCard `UID`) are properties of the item, not of the store, and live inside the content. A consumer that needs to map them to uuids does so in its own derived index.

## 6. Metadata

All metadata lives under a collection's `.meta` directory as one JSON document per uuid, named `.meta/<uuid>.json`. This single rule covers both the collection's own metadata, at `.meta/<collection-uuid>.json`, and every item's metadata, at `.meta/<item-uuid>.json`. Metadata is keyed by the stable uuid, never by the hash, so a change of content (which renames the content file) never moves or renames the metadata document.

Metadata documents are kept intentionally minimal: a field is present only when it is authoritative state that is absent from the content. Anything derivable from the content (an envelope, a summary, a category) is not stored, because it can always be recomputed by reading the item.

### 6.1 Item metadata

Every item metadata document carries two fields:

- `version`: the metadata schema version, currently `1`.
- `etag`: the item's content hash, identical to the `hash` field of the item's content filename. This is the invariant of the format: `etag` MUST equal the hash component of the content file. A consumer that finds them disagreeing MUST treat the content file as authoritative and recompute.

Items of kind `message/rfc822` additionally carry mail state, which has no place in the RFC 822 bytes:

- `flags`: a list of well-known keywords registered in the IANA "IMAP and JMAP Keywords" registry (for example `$seen`, `$answered`, `$flagged`, `$draft`, `$forwarded`, `$junk`, `$notjunk`, `$phishing`, `$mdnsent`).
- `keywords`: a list of custom, non-registered flags chosen by the user or application (for example `project-x`, `todo`).

A non-mail item (a calendar event, a contact) carries only `version` and `etag`, because its mutable state, status and categorisation all live inside the standardised item and its stable `UID` does not change across edits.

```json
{ "version": 1, "etag": "k4zsa3dpnvxha7l5", "flags": ["$seen", "$flagged"], "keywords": ["project-x"] }
```

```json
{ "version": 1, "etag": "n5xw6ylsmrqxg5dr" }
```

### 6.2 Collection metadata

A collection metadata document describes the collection itself:

- `version`: the schema version, currently `1`.
- `kind`: the media type of every item in the collection (`message/rfc822`, `text/calendar`, `text/vcard`, `text/plain`).
- `name`: the human-facing logical name (an IMAP mailbox name, a calendar title).
- `parent`: the uuid of the parent collection in the logical hierarchy, or `null` for a top-level collection.
- `color`, `description`, `order`: OPTIONAL presentation fields, mirroring vdir's collection metadata.

```json
{ "version": 1, "kind": "message/rfc822", "name": "INBOX", "parent": null }
```

```json
{ "version": 1, "kind": "text/vcard", "name": "Contacts", "parent": null, "color": "#3366ff" }
```

## 7. Writing

All writes are atomic through temporary file plus rename, and never require a lock. A temporary file has a period-prefixed name so it is ignored as an item; it is fully written and flushed (fsync) before being renamed into place, and a rename within a directory is atomic on every supported filesystem.

- Create an item: write the content to a temporary file, flush, rename it to `uuid.hash.ext`, then write `.meta/<uuid>.json` the same way. The content file MUST be durable before its metadata is written, so that a crash leaves at worst an orphan content file (harmless, garbage-collectable) rather than metadata referencing missing content.
- Change item state only (a flag or keyword change): rewrite `.meta/<uuid>.json` by temporary file plus rename. The content file is untouched and is never renamed, so routine mail flag changes cause no content churn.
- Change item content (an edited event or contact): write the new content as `uuid.newhash.ext`, rewrite `.meta/<uuid>.json` with the new `etag`, then delete the old `uuid.oldhash.ext`. If a crash leaves two content files sharing a uuid, recovery keeps the one whose hash equals the metadata `etag` and deletes the other. Immutable items (mail) never take this path.
- Delete an item: remove its content file and its `.meta/<uuid>.json`.

## 8. Reading

When enumerating items in a collection, every entry whose name does not start with a period is an item content file; every entry whose name starts with a period (the `.meta` directory, temporary files) is format machinery and MUST NOT be treated as an item. A file that cannot be parsed as a valid item filename, or whose extension is unknown, SHOULD be ignored rather than rejected, so that a store can be extended without breaking older tools.

## 9. Concurrency

Pimdir is lock-free by construction, inheriting Maildir's principle that uncoordinated processes coordinate only through atomic filesystem operations. There is no shared mutable file: item content is created under a unique uuid, and metadata is replaced as a whole document by atomic rename, so a reader always observes a complete file and never a torn one. Two writers racing on the same uuid resolve by last-writer-wins, which is acceptable for flag and keyword state. No process ever needs to lock a file or a directory to read or to write, on local, network or Windows filesystems alike.

## 10. Integrity and identity

Because the content hash appears both in the content filename and as the metadata `etag`, a store is self-checking: recomputing the hash of an item's bytes and comparing it to either value detects accidental corruption or tampering, with no separate manifest. The uuid provides stable identity across content edits and across re-synchronisation, while the hash provides content versioning and the dedup key. A consumer that distrusts metadata can always fall back to the content, which is authoritative for everything derivable, so a lost or stale metadata document is repaired by reparsing the item rather than by consulting any global structure.

## 11. Portability

Every on-disk name is composed of single-case base32 identifiers and a lowercase extension, and therefore contains none of the characters forbidden on Windows (`< > : " / \ | ? *`), no trailing period or space, and no reserved device name. Names are of bounded length, and collections are stored flat, so total path length stays well within MAX_PATH. The format makes no use of case to carry meaning, no use of symbolic links, and no use of characters or filenames that any of the target filesystems reject.

## 12. Relationship to Maildir, m2dir and vdir

Maildir, m2dir and vdir are recovered as profiles of pimdir:

- A Maildir or m2dir folder maps to a collection of kind `message/rfc822`. Flags that Maildir encodes in the filename suffix, and that m2dir keeps in a `.meta/<id>.flags` file, move into the item metadata `flags` and `keywords` fields, removing the rename-on-flag-change cost and the colon that makes Maildir unusable on Windows.
- A vdir calendar or address book maps to a collection of kind `text/calendar` or `text/vcard`. vdir's collection metadata files (`color`, `displayname`) move into the collection metadata document, and per-item metadata is reduced to `version` and `etag`, because everything else already lives inside the iCalendar or vCard item.

## Appendix A. Example store

```
mystore/
  .pimstore                                           { "version": 1 }
  mfsg2ylomrugs4zann2xg5dboaqq.../                    collection (a mailbox), name = INBOX
    .meta/
      mfsg2ylomrugs4zann2xg5dboaqq....json            { "version":1, "kind":"message/rfc822", "name":"INBOX", "parent":null }
      7c8e2b14nvxha7l5mrzgc3tp.json                   { "version":1, "etag":"k4zsa3dpnvxha7l5", "flags":["$seen"], "keywords":[] }
      a1b2c3d4mrsw4z3pnvxgg5dr.json                   { "version":1, "etag":"nbqwy3dpo5xca7l5", "flags":["$flagged"], "keywords":["project-x"] }
    7c8e2b14nvxha7l5mrzgc3tp.k4zsa3dpnvxha7l5.eml
    a1b2c3d4mrsw4z3pnvxgg5dr.nbqwy3dpo5xca7l5.eml
  nbswy3dpeb3w64tmmqqq.../                            collection (a calendar), name = Work
    .meta/
      nbswy3dpeb3w64tmmqqq....json                    { "version":1, "kind":"text/calendar", "name":"Work", "parent":null, "color":"#3366ff" }
      19af83bcmrxw6z3pnvsa.json                       { "version":1, "etag":"q1w2e3r4t5y6u7i8" }
    19af83bcmrxw6z3pnvsa.q1w2e3r4t5y6u7i8.ics
```
