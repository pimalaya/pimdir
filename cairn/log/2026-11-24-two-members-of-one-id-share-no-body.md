---
cairn: log
change: two-members-of-one-id-share-no-body
landed: 2026-11-24
---

# Two members of one ID share no body

Found by neverest's live test on Stalwart (tests/moves.rs `a_move_into_a_message_stating_its_id_keeps_both`, io-pimdir 0.20.2): A in Left and B in Right state one `Message-ID`, subject, date, sender and size, B listed before A moves to Right. B's first upgrade linked A's body by SYNC §6's agreement, as written, before Right held any other member stating the hint; once the move landed A beside it (minted, holding its own body), Right held two members sharing A's body and B's binding pointed a delete or a flag of "A's body" at B. Nothing IMAP lists tells the two apart without RFC 8474 `EMAILID`, which neverest cannot request yet.

The owner's ruling of 2026-11-24 (io-pimdir cairn/changes/a-same-id-message-keeps-its-body, option A): where a collection holds, or a listing brings, two members stating one `Message-ID`, no member of them takes a body by agreement; its body is fetched, or kept from its own landing. Correct on every server, one download per such duplicate. sync-draft-15 and storage-draft-17 are edited in place.

## SYNC.md §6, linking instead of fetching

- *Two members stating one hint in a collection share no body by agreement*: a placement under its bare hint beside a member under a key minted from it links only under its own server object id, else fetches. Vector 222 (Archive's agreeing row would have been linked into INBOX/77 beside 78).
- The write giving a member under a minted key the body the bare one holds releases it from the bare one, unless the bare one needs it, a source states one server object id for both, or another minted member held that body before (a fetch confirmed the sharing). Vector 223 (a copy into Archive releases the body its bare member had linked); vector 215 keeps its rows, its three copies sharing the body before the fourth.
- *Note*: a body linked across collections before the collection held another member of the hint, differing from that member's, stays: nothing a listing states tells it apart.

## STORAGE.md §9, §11.4, §14

- §14 the load: a `Handles` selection over a mail collection also reads every item under a key minted from a key it reads, so an upgrade naming the bare member alone sees the other (vector 222).
- §14 *A body two members stating one hint would share*: the release the write applies, as §11.4 releases a body (vector 223); §11.4 and §9 point at it.

io-pimdir follows in the commit checks/io-pimdir.rev will name (io-pimdir cairn/log/2026-11-24-two-members-of-one-id-share-no-body.md).
