---
cairn: tasks
change: compared-with-notmuch
---

## Done

- [x] API inventory of notmuch 0.40 from notmuch.h and its man pages, compared with STORAGE, SYNC, SEARCH and io-pimdir (proposal.md, Part 1)
- [x] Probe Maildir of five crafted messages: stemming, accent folding, threads, malformed queries, through both CLIs
- [x] bench/: maildirify.py (Enron to Maildir, flags, the rewritten copy), the harness (a Maildir connector driving io-pimdir's engine, the refresh, in-process query timing), tier.sh, queries.sh with queries.tsv, incr.sh, chain.sh
- [x] 517k tier: import, sizes, 17 queries, no-op, 1,000 new, 1,000 flag changes, tagging; 52k and 517k imports without fsync
- [x] 1M tier (two Enron copies, 1,034,802 messages): import and queries, folded into proposal.md
- [x] pimdir: `mid:`, times of day, notmuch's two orders beside `title`, `sender` and `relevance` (the-query-serves-every-client, search-draft-16, 2026-11-21), three of notmuch's lines in Part 1
- [x] Owner decisions of 2026-11-21 (proposal.md, The plan), each line below moved to the change that carries it

## Carried by other changes

- [ ] The planner and coverage (performance-audit-2026-11-05 F1, F8; `COUNT_UNINDEXED` on `items_by_changed`): io-pimdir cairn/changes/as-fast-as-notmuch, phase 2
- [ ] Bodies flushed by page, integer object ids, interned addresses: the-write-path-before-the-freeze, prototyped by io-pimdir's as-fast-as-notmuch, phase 3
- [ ] Local labels and per-item properties: an-item-keeps-local-state
- [ ] Exact words, `~`, `/…/` and `{…}` reserved, the extraction status open: the-query-reserves-its-later-forms
- [ ] `thread:{query}` and every subquery, the thread summary, `list:`, address harvesting, recursive collections, proximity, regex, stemming: a-query-reads-across-domains
- [ ] The CLI's JSON output as the integration contract: io-pimdir cairn/changes/the-json-output-is-the-integration-point
- [ ] Decryption, later: io-pimdir cairn/changes/a-decryption-break
