---
cairn: change
id: conventions-leave-the-core
status: landed
created: 2026-10-30
---

# Operational detail and conventions leave the normative core

## Why

Edit 8 of the pimdir stable-release plan (2026-10-30), from the scope opinions of the consolidated pimdir review. STORAGE freezes first, and every rule left in a part freezes with it:

- SYNC §4 (SYNC.md:89-141 at 8b2e8b6) carries provider page sizes (the IMAP, Graph, Gmail, JMAP and DAV table), received-date filter margins and vendor quirks. They are operational, measured and revised, and a SYNC minor for each revision is noise; the neutral contract (pages, cursor, heads, the margins a connector owes the scope) stays normative.
- The GTD conventions (GUIDE §17 and §18, vectors/gtd, the local time collection of STORAGE §14.3, `list_replied`'s use) are what make unfog and Pimalaya Android interoperate, so they stay in the project, but in a document of their own, versioned apart, so the core freezes without them.
- Annex B intents stay in STORAGE: no separate registry (decided; the forward-compatibility half landed as a-capability-added-later-is-read-where-stated).

## What

- SYNC §4: the page-size table, the per-provider rows and the vendor names leave for GUIDE §10 (or connector notes in io-pimdir); SYNC keeps the neutral rule (a page size the connector chooses, lowered on a timeout or a `413`, never raised past a measurement) and the scope margins as rules without vendor names where possible.
- A new conventions document, GTD.md, informative on its own version line (`gtd-draft-01`, requiring storage-draft-05 and search-draft-05), holding GUIDE §17 and §18, the local time collection's id and name (STORAGE §14.3), and vectors/gtd; STORAGE keeps the statements they use (`list_replied`, the `U+0001` ids rule of §9.2) as store facts.
- README Layout and Specification, OVERVIEW, AGENTS.md, checks/names.sh (its document list) and checks/vectors.py follow.
- No Annex B registry document.

## Lands in

sync-draft-05 and storage-draft-05 (the §14.3 move); the conventions document starts at its own first draft.

## Decided (2026-10-30)

- The document is GTD.md, versioned apart as `gtd-draft-01` (orchestrator of the stable-release effort). It is informative, as the moved text already was: GUIDE §17 called itself "a reading of `task_summary.categories` and `status`, not a rule of the store" and vectors/gtd/ said "informative like the guide".
- STORAGE §14.3 keeps a local calendar collection as a store fact (a collection no source syncs, written directly); the `\u0001time` id and the `time` name move to GTD.md §2. `list_replied` stays in STORAGE §14.1, a store read any client may use; its review use is GTD.md's.
- vectors/gtd/ keeps its path, owned by GTD.md, so no consumer's vector path moves.
- Provider detail went to GUIDE §10's connector notes, not to io-pimdir; the untestable "MUST NOT raise one past these without a measurement" became "SHOULD lower it after a timeout or a `413`".
