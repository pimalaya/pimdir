---
cairn: log
change: a-pending-create-is-withdrawn-whatever-the-rights
date: 2026-11-15
---

# A pending create is withdrawn whatever the rights

Found by the live campaign of 2026-11-15: a message added to a Graph folder other than Drafts, rejected by every sync, could not be deleted while the source's deletes were off ("does not support mail.message.move: item.create or item.delete is disabled"). STORAGE §15.6 asked every source binding the item, and a pending create is a binding, though withdrawing it pushes nothing (SYNC §3, §7). Proposal: cairn/changes/a-pending-create-is-withdrawn-whatever-the-rights.

## Rules and their checks

- **`load_item_capabilities` answers `held`** (STORAGE §14.1): the source's `base_present`, 0 for a pending create, 1 for a delivered one. checks/invariants.sh "capability: an item answers for the sources binding it alone, each holding it" and "capability: a pending create is bound unheld …", both failing on the old statement; queries/signatures.json restated.
- **A remove, a move or a copy leaves a source holding nothing out** (STORAGE §15.6): a remove withdraws the create, a move or a copy meets that source in the target alone, asked there an `add`'s capabilities, as every source of the target binding nothing of the item is; a `set-flags` and an `update` still ask it, riding on its add. No check of this repository observes a producer's gate or a drain: io-pimdir's tests/capabilities.rs `a_pending_create_is_withdrawn_whatever_its_source_may_delete` holds it, failing on the old gate with the live refusal. GUIDE §12 follows.
- Checked on the working tree (2026-11-15) with the change of the same day: `nix flake check path:$PWD` green; checks/tags.sh fails until the owner bumps storage-draft-11.
