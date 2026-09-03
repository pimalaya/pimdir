---
cairn: log
change: informative-layer
date: 2026-09-03
---

# An overview before the parts and a guide after them

The three parts braided three things a reader wants at different times: the model, the rules, and the procedures that carry the rules out. A newcomer had no way in that did not start at a column name, and an implementer had the write transaction, the collector's lock order and the sync walk as paragraphs to reassemble into steps.

The standard now has two informative documents around the three normative parts, on the pattern of an architecture document and an implementation-notes companion beside an RFC. OVERVIEW.md explains the model with no table, column or statement named, one section per concept, each ending with the part that binds. GUIDE.md restates the parts as numbered procedures and decision tables, naming the statement under queries/ and the vector under vectors/ at each step, and opens with a conformance checklist. Neither carries an RFC 2119 word, neither adds a rule, and each says the parts win on any disagreement, which is what keeps them from becoming a second source of truth.

Three documents rather than six: the model is shared across the parts, so one overview serves all three, and one guide is enough since the store's procedures are short and the index's is one loop. Terminology stays in the parts, bound to columns, rather than moving to the overview, which would have cost it the precision that makes it binding.

README.md lists the five documents in reading order, AGENTS.md states what the informative layer may and may not contain and extends the forcing rule to it, and each part points at the sections of the overview and the guide that concern it.
