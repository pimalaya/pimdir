---
cairn: log
change: a-relocation-lands-on-the-flags-it-carries
landed: 2026-11-24
---

# A relocation lands on the flags it carries

Found by the live test night of 2026-11-23 (.lanes/live/report.md of the workspace, finding 1.1), a silent loss: through himalaya's pimdir queue, a flag set (`\Seen $Important`) then a move of the same message were drained by neverest; IMAP `UID MOVE` relocated the member with the flags the server held (`\Flagged`) and answered its `COPYUID`, and the landed create took the staged flags as its base. The store then read `Clean` while the server differed, so the next listing pulled `\Flagged` back over the user's set, on the server and in the store, with no warning. Reproduced three times on Stalwart.

SYNC.md is edited in place (sync-draft-15 is untagged); storage-draft-17 and search-draft-17 do not move.

## SYNC.md §4, a relocation names the member it made

- A create landed on the handle a relocation stated takes as its base the flags the relocated member carries, the base of the member removed, a relocation keeping the flags its source held, beside the body staged on the create and the revision the outcome states. A flag change staged before the move stays owed and is pushed by the next run of the target. Vector 214 (the base took the staged flags; the owed set was pulled back over).
- Vector 196's note restates the rule; its data, where the staged flags equal the base, does not move.

io-pimdir follows in the commit checks/io-pimdir.rev names.
