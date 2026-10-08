---
cairn: log
change: trash-disposal-is-a-move
date: 2026-10-08
---

# A delete that ends in a trash is staged as a move

SYNC §7 and GUIDE §11 now say which mutation fits a delete meant to land in a trash: a `Move` into it, `Remove` being for a final delete. Informative only: no rule, statement or schema moved, so no check guards it and the draft number stays.

## Why

SYNC §4 leaves the disposal of a plain delete to the consumer. Pimalaya Android staged a `Remove` and pushed it as a move into the server's trash: the store recorded the item gone while the server held it in the trash, which showed nothing until its next listing (seen 2026-10-08). The app now stages a `Move` (its change `local-first-actions`).
