---
cairn: log
change: draft-13-a-refused-push-shows-on-its-receipt
landed: 2026-11-15
---

# Draft 13: a refused push shows on its receipt

The rule the owner decided on 2026-11-15 (cairn/changes/a-refused-push-shows-on-its-receipt, D1 to D5, each recommendation taken; cairn/log/2026-11-15-a-refused-push-shows-on-its-receipt.md) changed storage and sync after the draft-12 tags of the same day. The three parts move together: **storage-draft-13**, **sync-draft-13** and **search-draft-13**, search because its Status line requires storage-draft-13. conventions/gtd.md stays gtd-draft-04 and requires the new drafts. Draft-12 was tagged and never released: no app shipped a store of it.

## What moved

- The Status lines, README.md, AGENTS.md and the version texts: STORAGE §4.2, §14 and §17, SYNC §10 and §12, SEARCH §2 and §12, GUIDE §1.
- `init_store_meta` writes `storage-draft-13`, `init_index_meta` writes `search-draft-13`.
- checks/invariants.sh: a store of draft-12 is refused under draft-13, and the scenarios stamping a draft's name, the sync version and the index version name draft-13.

## Consequences

Every store and sync state of an earlier draft is refused, never migrated, and an index of an earlier draft is rebuilt: each app rebuilds its store once it takes the io-pimdir following this draft. A connector answering `Refused` for a change the remote refuses as it stands is what makes the hold work; one that cannot tell keeps answering `Rejected`, which retries as before.

Checked on the working tree: `nix flake check path:$PWD`. checks/tags.sh passes once the three tags name the commit checks/io-pimdir.rev is pinned in.
