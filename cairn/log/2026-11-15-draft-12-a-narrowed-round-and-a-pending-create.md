---
cairn: log
change: draft-12-a-narrowed-round-and-a-pending-create
landed: 2026-11-15
---

# Draft 12: a narrowed round and a pending create

The two rules the live testing campaign of 2026-11-15 changed after the draft-11 tags (cairn/log/2026-11-15-a-narrowed-round-proves-only-what-its-enumeration-lacks.md, cairn/log/2026-11-15-a-pending-create-is-withdrawn-whatever-the-rights.md), the owner taking reading (a) of the first on 2026-11-15. The three parts move together: **storage-draft-12**, **sync-draft-12** and **search-draft-12**. Storage and sync changed; search changed nothing of its own and moves because its Status line requires storage-draft-12, a store of draft-11 being refused (STORAGE §4.2). conventions/gtd.md stays gtd-draft-04 and requires the new drafts.

## What moved

- The Status lines, README.md, AGENTS.md, and the version texts: STORAGE §4.2 (`format_version`), §14 (the version of the sync state) and §17 (the conformance example), SYNC §10 and §12, SEARCH §2 (`index_meta.format_version`) and §12, GUIDE §1's conformance checklist.
- `init_store_meta` writes `storage-draft-12`, `init_index_meta` writes `search-draft-12`.
- checks/invariants.sh: a store of draft-11 is refused under draft-12 (the previous draft, where draft-10 stood), and the scenarios stamping a draft's name, the sync version and the index version name draft-12.

## Consequences

Every store and every sync state draft-11 wrote is refused, never migrated (STORAGE §4.2, SYNC §10), and an index of draft-11 is rebuilt: each app rebuilds its store once it takes the io-pimdir following this draft. A connector narrowing its listing without handing `enumerated` infers no delete from a narrowed round (SYNC §5): neverest's IMAP and Gmail band rounds, which hand it only off a band, keep what they do not list until they hand it.

Checked on the working tree: `nix flake check path:$PWD`. checks/tags.sh passes once the three tags name the commit checks/io-pimdir.rev is pinned in.
