---
cairn: log
change: the-freeze-plan
landed: 2026-11-25
---

# The freeze checklist is rewritten

The checklist of the freeze commit in cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md named files the night of 2026-11-22 removed (queries/, GUIDE.md, checks/names.sh, checks/invariants.sh) and search-draft-10. cairn/changes/the-freeze-plan/checklist.md now holds the steps read against the trees of 2026-11-25: the gates before the commit, the Status lines and recorded names (`storage-v1`, `sync-v1`, `search-v1`), the draft-only sentences, checks/frozen.sha256 and checks/appended.py, io-pimdir 1.0.0 beside it, and the owner's rule of the same day that no tag is pushed before CI is green on the exact commits it names. The consumers stay on io-pimdir 0.20.x for this freeze (owner, 2026-11-25).

No part's text, vector or check moves. Guard: none needed, the checklist being a procedure the rehearsal (its step 3) runs on scratch copies before the commit.
