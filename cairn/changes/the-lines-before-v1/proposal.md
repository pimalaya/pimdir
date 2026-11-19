---
cairn: change
id: the-lines-before-v1
status: active
created: 2026-11-19
---

# The lines before v1

## Why

Before the v1 tags, every open line of pimdir/cairn/changes/*/tasks.md and io-pimdir/cairn/changes/*/tasks.md sorted into one of three: **blocks v1** (moves what storage-v1.0.0 or sync-v1.0.0 freezes, or is a loss or a loss reported as success, and must land before the tags), **after v1** (class after or any, consumer or app work, measurements, future parts), **obsolete** (done or superseded, evidence cited). Read on 2026-11-19 against pimdir at eab6b05 plus the working tree, io-pimdir at e78ef92 (v0.17.0) plus the working tree, and the consumers' working trees. No change folder is deleted; each keeps its lines, this is the index.

## Where things stand

- Draft-14 (storage, sync, search) is landed and checked: `nix flake check` passes (263 of 263 statements run), checks/tags.sh passes (no draft-14 tag yet), checks/implementation.sh passes with checks/io-pimdir.rev at io-pimdir v0.17.0 (e78ef92), every vector case run, none pending.
- Tags for the owner, on the commit that pins e78ef92 in checks/io-pimdir.rev: `storage-draft-14`, `sync-draft-14`, `search-draft-14`; `gtd-draft-04` too if checks/tags.sh `--released` is to pass at the freeze, since it reads conventions/gtd.md as a part and no gtd-draft-04 tag exists.
- The freeze checklist (cairn/log/2026-11-13-the-freeze-gate-is-rehearsed.md, item 9) names search-draft-10; the current draft is search-draft-14. The log is immutable: the freeze commit reads the current draft names, not that list's.

## Blocks v1

The freeze gate of README.md checks the reference implementation alone, and io-pimdir has no open line that blocks it. What stands before the tags:

1. pimdir adopt-cairn/tasks.md:10: end the draft relaxation at the freeze (item 6 of the freeze checklist). A step of the freeze commit itself.
2. pimdir audit-2026-11-12/tasks.md:46, Y2 (before sync-v1): neverest landed fake-server tests of the `Remove` contract on 2026-11-19; a run against a real server is owed (the owner's grant).

A8 to A11 (Android, class before) and N1 were closed in their repositories on 2026-11-19 (android cairn/log/2026-11-19-the-audit-lines-a7-to-a11.md, neverest cairn/log/2026-11-19-a-dry-run-replica-is-a-consistent-copy.md), uncommitted at the time of this reading, and are ticked in audit-2026-11-12. Line 2 is neverest's, a consumer marked "before"; the owner decides whether it holds the tags or follows them.

### Owner decisions before sync-v1 (ruled 2026-11-19)

The owner took every recommendation below on 2026-11-19: the read-back after v1, additive; the file with no row landed before the tags (pimdir cairn/log/2026-11-19-a-file-with-no-row.md, the sync vectors at format 8, vector 172, no draft bump); the fence after v1, as a storage-v1 minor adding a `store_meta` column, Android exempt. The two io-pimdir changes are `active`, accepted and deferred past the tags. None of the three blocks v1 now; the file with no row moves checks/io-pimdir.rev, since v0.17.0 refuses the sync vectors' format 8.

As the three stood before the ruling:


- io-pimdir a-push-reads-back-the-server-bytes (draft, 7 lines): after v1 if a push outcome only gains an optional body (additive to SYNC §4); before sync-v1 if SYNC §5 is to say the base MUST be the server's body, which changes engine behaviour and vectors sync-v1 pins. Recommendation: after v1, additive; the local body still holds what the server dropped, so nothing is lost meanwhile.
- pimdir two-silent-losses-fold-into-draft-08/tasks.md:16: a sync vector stating a file with no row needs a field in vectors/schema/sync.schema.json, which joins checks/frozen.sha256 at sync-v1 (O13). Before the tags, or never without a new vector format. Recommendation: before, if the owner still wants it, as one optional field.
- io-pimdir an-owner-write-checks-its-fence (draft, 5 lines): decided after v1 by Q9 (2026-11-12); a decision brief is in that change's proposal.md (2026-11-19). Not blocking.

## Counts

- pimdir, 113 open lines read, 8 since ticked (T7, P5, N1, A7 to A11): blocks v1 2, after v1 76 (C5 included), obsolete 25, owner question 1.
- io-pimdir, 68 open lines read, 6 since ticked (release-hygiene 3, the two draft-14 pin lines, the-default-enqueue-strips:11): blocks v1 0, after v1 22, obsolete 28, owner decision 5 (the fence) and 7 (a-push-reads-back-the-server-bytes, an owner question); plus 8 lines the changes of 2026-11-19 opened (one-no-replace-move 1, a-purge-of-chosen-items 2, the-store-rules-the-clis-restate 4, the-merge-verdict-is-public 1), all after v1.

Since, on 2026-11-19 (the owner's rulings): pimdir's owner question is landed (two-silent-losses:16), so pimdir has no owner question left; io-pimdir's 12 owner lines are after v1 (the fence 5, the read-back 7), an-ambiguous-intent-awaits-confirmation landed (7 lines ticked), a-page-lands-in-few-statements abandoned (its 10 lines ticked), and the-store-rules-the-clis-restate ticked 3 of its 4 lines (the CLIs' own stays, after v1).

The per-line table is tasks.md.
