---
cairn: log
change: mail-write-names-from-himalaya
date: 2026-11-02
---

# The mail write names himalaya declares

Folded into storage-draft-08, untagged, no number bump. Lands cairn/changes/mail-write-names-from-himalaya, reviewed by the maintainer on 2026-11-02; pimdir master first took the unmerged audit-2026-10-31 branch as one squashed commit, so the change lands on the draft-08 text.

- **Two flags out of `mail.flags.keywords`** (STORAGE Annex B, B.1; GUIDE §13 Check and Declare). `mail.flags.important` (`$Important`, RFC 8457) and `mail.flags.junk` (`$Junk`, RFC 9051 §2.3.2) are read only where a row states them, as `calendar.component.vtodo` is: a source with a row for one, `none` included, is gated by it, one without by `mail.flags.keywords`, so a declaration written before them reads as it did and Gmail's or Graph's fields are declarable without claiming every keyword. B.1 now says a flag names its capability ignoring ASCII case, as IMAP compares flags, which io-pimdir already did for the four system flags.
- **`collection-rename` and `collection-delete`** (STORAGE Annex B, B.2, §15.6 Intents; GUIDE §13 Check; OVERVIEW's intents). Capabilities `collection.rename` and `collection.delete`, in the base set. Both address the collection the action is queued on, its anchor, which the payload does not restate, so a store rename leaves the row addressing it as `target_collection` does: `{ "v": 1, "source": id, "name": label }` and `{ "v": 1, "source": id }`. A rename keeps the parent, a reparent staying out until the payload of a move is decided; a sibling holding the name parks, the collection already so named acknowledges. The performer SHOULD follow a rename with `rename_collection` where the id derives from the name. A delete never takes another collection: a performer finding children parks deleting nothing, since Graph would delete them unnamed and IMAP or JMAP refuse. The store removes no item and queues no `remove` for a delete; the deletion reaches other sources only through SYNC §5's enabled collection deletion, which settles the proposal's open question on the items it removes.
- **Left out**, as proposed: the draft verbs (an `add` with `\Draft` and a `submit`), `submit.cancel` (the queue's `cancel_action`, or outside any replica), mailbox moves.

Checks: payloads/collection-rename.v1.schema.json and payloads/collection-delete.v1.schema.json, six cases in vectors/payloads.json (47), the action enum of vectors/schema/payloads.schema.json, vectors/manifest.json restated; checks/vectors.py fails without the schemas (the documents' shapes against payloads/, a valid and a malformed case per schema), and checks/names.sh reads the four new Annex B rows (`importance` joins its listed words). The flag rule has no vector format in this repository: io-pimdir's capability tests guard it. `nix flake check path:$PWD` green.

Followers: io-pimdir (the constants, the flag gate, the two intents' codecs and anchors); himalaya maps `collection.rename` and `collection.delete` onto `mailbox.rename` and `mailbox.delete` once its shared verbs exist; neverest performs the intents when its connectors grow the verbs.
