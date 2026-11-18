---
cairn: log
change: the-draft-14-lines
date: 2026-11-18
---

# The audit lines before v1: C1, C2, C4, Y2

Lines of cairn/changes/audit-2026-11-12 marked "before", folded into cairn/changes/the-draft-14-lines. Version names untouched: storage-draft-13 moves with the draft-14 bump.

## Rules and their checks

- **Which store is the earlier** (STORAGE §4.2, §16, §17), line C1: format versions are ordered, none first, then drafts by the decimal number after `storage-draft-`, then releases by a major without a leading zero, every draft before every release; a refusal for the `format_version` says which is the earlier and what that asks, an earlier store drained by its engine then set aside, a later one asking for a later program, an unread marker ordered neither way, never advising deletion. calendula's parsing, which reads every draft store as newer under `storage-v1`, is what the rule rules out. New vectors/versions.json (format 1, 24 cases, its schema under vectors/schema/), bound on every profile; checks/vectors.py derives each order itself and requires a case of each order, failing on a case altered ("'storage-draft-014' against storage-draft-13: unknown is not later"). io-pimdir's `version::PimdirFormatRefusal` is the wording the applications show (its log of 2026-11-18, one-refusal-for-another-version).
- **Instructions stripped by default** (§18 unchanged), line C2: io-pimdir's `enqueue_with_body` now strips, `enqueue_user_body` keeping a body the user wrote; no format change.
- **Queue rows under the store's identity** (§4.5, §15.4), line C4: re-checked at io-pimdir d6ca71a, already met by `PimdirActionHandle`; closed for the crate, the CLIs following.
- **Y2** re-checked at neverest 0c10335: the code follows both rules, the server tests asked are still missing; kept open as neverest's.
- vectors/manifest.json restated; `checks/vectors.py .` green (24 version orders, 171 sync cases); vectors/README.md names the file and its format.
