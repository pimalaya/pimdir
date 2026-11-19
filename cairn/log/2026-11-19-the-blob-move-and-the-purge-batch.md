---
cairn: log
change: audit-2026-11-12
landed: 2026-11-19
---

# The blob move and the purge batch

io-pimdir closed its half of two audit lines of class any, nothing in the format moving:

- **T7**: the store's blob move is `PimdirBlobMove`, `renameat2` with `RENAME_NOREPLACE`, then `link(2)`, then the exclusive create and copy where the link is denied (STORAGE §5 and its Android note), ported from the Android app's tested move and public, so the app can drop its copy (io-pimdir cairn/log/2026-11-19-one-no-replace-move.md).
- **P5**: `PimdirStore::purge_items` purges chosen retained items in one transaction through `PURGE_ITEM`, for neverest's per-account sweep (io-pimdir cairn/log/2026-11-19-a-purge-of-chosen-items.md). A sibling statement taking an account stays a question for a minor after v1.

A7 to A11 and N1 are ticked on the logs of their repositories (android cairn/log/2026-11-19-the-audit-lines-a7-to-a11.md, neverest cairn/log/2026-11-19-a-dry-run-replica-is-a-consistent-copy.md); Y2 stays open, its tests being against a fake server only. C5 is proposed in io-pimdir cairn/changes/the-store-rules-the-clis-restate and stays open. checks/io-pimdir.rev moves to io-pimdir v0.17.0 (e78ef92), the release following draft-14; `nix flake check`, checks/tags.sh and checks/implementation.sh pass on it. The two io-pimdir changes above are not in that pin: they wait for io-pimdir's next release.

Capabilities moved: none in pimdir.
