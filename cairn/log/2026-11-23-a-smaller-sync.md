---
cairn: log
change: a-smaller-sync
landed: 2026-11-23
---

# A smaller sync, the reference implementation only

No part of the standard moved: SYNC.md, STORAGE.md, SEARCH.md, migrations/, vectors/ and payloads/ are as fb56c83 left them, and sync-draft-15 stays untagged. checks/io-pimdir.rev now names io-pimdir 7f16b27 (e942afb and the re-signed hash references), whose suite passes this tree's vectors unchanged.

The night of cairn/changes/a-smaller-sync changed io-pimdir under one rule, every yield of a run but its loads and every row it leaves the same as 176e0b7's, proven by a differential oracle of the old engine against the tree (100,000 generated multi-source scenarios and the 200 vectors at the end, 0 differences; three planted bugs caught first): shared helpers, one conflict-policy verdict, a load naming no link reading no hub, `settled_collections` for a caller to skip what owes nothing, and whole-collection reads streamed. The no-op sync of the 517k store went from 89 to 68 ms, and to 19 ms skipping settled folders (notmuch new 47); a full round 17 to 25% faster. io-pimdir's cairn/log/2026-11-23-a-smaller-sync.md has the moves and the measures.

What the change folder holds for later, none of it binding: report.md (the owner's reading), moves.md (each change, what it would move, the rule changes C1 to C7 and wire changes W1 to W3), candidates/ (tests pinning nine rekey behaviours that depart from SYNC §4 and §8, two of them silent losses, and the drain keying a copy apart where `store.mutate` joins), and SYNC-rewrite.md with its ledger (rules.tsv, rules-merged.tsv, tools/ledger.py, owners.md, review/), a rewrite at 18,019 words of today's 19,036 that three adversarial reviews and a fix pass left meaning the same, not landed.
