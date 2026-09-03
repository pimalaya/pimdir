---
cairn: log
change: storage-and-concision
date: 2026-09-03
---

# SPEC.md is STORAGE.md, and the three documents say only what they mean

The three parts are named for what they specify: STORAGE.md, SYNC.md, SEARCH.md. Each is implemented independently, and a citation reads `STORAGE §9` where it read `SPEC §9`; section numbers are unchanged. Earlier log entries keep the old name, logs being immutable.

The three documents were then rewritten to the organisation's writing guidelines, as an aim rather than a rule: every sentence carries a rule or the one reason for it, a paragraph runs three rendered lines at most, history and measurements go to the log. STORAGE.md went from 657 lines to about 470 with every MUST, every statement name and every encoding kept; SYNC.md and SEARCH.md were tightened the same way.

Verified by the same checks as before: both schemas apply, 130 statements prepare, and every vector re-derives or checks.
