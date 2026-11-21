---
cairn: log
change: the-freeze-plan
landed: 2026-11-21
---

# The JSON output is a contract

the-freeze-plan D4 amended (the owner's ruling of 2026-11-21, after compared-with-notmuch): the `pimdir` operator binary stays outside io-pimdir's 1.0 contract but for the JSON output io-pimdir's the-json-output-is-the-integration-point names, the integration point in place of a C library. What `--json` prints for `search`, `count`, `show`, `thread`, `tag`, `item list`, `item show`, `collection list`, `queue list`, `queue status`, `store info` and `version`, and the failure object `pimdir-error`, is stable within a major: a minor adds keys, and values only to vocabularies declared open; anything else moves the major. One probe, `pimdir --json version`, states that major as `formatVersion`, io-pimdir's own major, and no payload carries it; no `--format-version` is served until a second major exists.

No normative part moves: STORAGE, SYNC and SEARCH say nothing of the binary. The rule lives in io-pimdir's cairn/spec/cli.md and its check is io-pimdir's tests/json_contract.rs, which pins each payload's schema against a committed copy (io-pimdir cairn/log/2026-11-21-the-json-output-is-a-contract.md).

The pending decision on the binary's schema `$id` after 1.0 (tasks.md §5 open line) now meets `formatVersion`: below 1.0 the `$id` names `v0.<minor>` while `formatVersion` prints `0`.
