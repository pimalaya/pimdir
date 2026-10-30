---
cairn: log
change: conventions-leave-the-core
date: 2026-10-30
---

# Operational detail and conventions leave the normative core

Edit 8 of the pimdir stable-release plan. Every rule left in a part freezes with it, and SYNC §4 carried measured provider page sizes, vendor examples and an untestable MUST, while GUIDE §17 and §18 carried the GTD conventions two applications share.

- **SYNC §4, §5** (normative): the page-size table and its "MUST NOT raise one past these without a measurement" left; a connector chooses its page size within what the source accepts and SHOULD lower it after a timeout or a `413`. The vendor examples (Graph, Gmail, Google Agenda and People, Nextcloud and ownCloud, Google Drive, Google's `404` on a move, Gmail's Pacific midnight, Graph's `@removed`) left the rules, which keep IMAP, JMAP and DAV as examples; no rule changed meaning.
- **GUIDE §10** (informative): "Connector notes" now hold the table and every vendor detail, provider by provider.
- **GTD.md** (new, informative, `gtd-draft-01`, requiring storage-draft-05 and search-draft-05): GUIDE §17 (tasks by categories, the views, the writing table) and §18 (time entries) moved there whole, with the local time collection's id `\u0001time` and name `time`, and its vectors (vectors/gtd/, which keep their path). Informative because the moved text already was; versioned apart so STORAGE freezes without it. GUIDE keeps §1 to §16.
- **STORAGE §14.1, §14.3, §16** (normative): a local calendar collection is a store fact (no source syncs it, the owner writes it), its id a convention's; `list_replied` stays a store read, its review use GTD.md's.
- **README, OVERVIEW, AGENTS.md** name GTD.md; checks/names.sh reads it, checks/vectors.py reads the view table from GTD.md §1, flake.nix puts it in the checked fileset.
- **No Annex B registry**: the intents stay in STORAGE Annex B, versioned with it (decided by the plan; the forward-compatibility half landed as a-capability-added-later-is-read-where-stated).

checks/vectors.py's GTD view check reads GTD.md now and fails if the table is gone from it (it read GUIDE.md before, where the table no longer is). `nix flake check path:$PWD` passes. unfog and Pimalaya Android cite gtd-draft-01 in their own cairns.
