# Review C: F6, F8, F10, F13, F14, F16, F17, and family none in §7 and §8

Scope: every ledger row of families F6, F8, F10, F13, F14, F16, F17 (136 rows, the new-only table rows included) and the 36 rows of family `none` in §7 and §8, each read in its base paragraph against the rewrite text, plus every cell of tables A, B and D and the rewritten paragraphs around them.

## Findings

- **o10-L628-s5 (table D, mutation row).** Base: "A mutation's `Edit` states `Overrule` before its upsert when it carries `overrule`, and an `Edit` or a `Remove` states `Settle` when its `resolves` names the item's conflict (§7)". Rewrite: column "Ops in batch order", cell "`Overrule`, the upsert; `Settle` when an `Edit`'s or a `Remove`'s `resolves` names the item's conflict", order constraint "an `Edit` carrying `overrule` states `Overrule` before its upsert". Change: the base set no position for `Settle`, but a column headed "in batch order" now puts `Settle` after the upsert, which contradicts STORAGE §14 (`Settle { handle }`: "the next upsert of `handle` is a person's resolution"), so `Settle` must come before its upsert. An engine following the table writes a `Settle` that applies to no upsert, or to the wrong one. Severity: changed.

- **o06-L476-s1 / o09-L591-s1 (table B, row "the missing body read, differing").** Base (§6): "under `prefer-incoming` the item adopts it, and under `prefer-existing` keeps its own, the conflict cleared either way and the body not adopted kept and reported (§9), when the item holds a body; one holding none waits, recorded as `manual` records it, for the fill that reads its own (§9)." Rewrite: `manual` cell "the policy applies as to a carried body, when the item holds a body, one holding none waiting, recorded as `manual` records it, for the fill that reads its own: `manual` keeps the conflict, ..."; `prefer-incoming` cell "adopts the incoming body, the conflict cleared"; `prefer-existing` cell "keeps the item's, the conflict cleared". Change: the condition that governs the two `prefer-*` policies ("when the item holds a body", else wait) now sits only in the `manual` column, so the `prefer-*` cells read as unconditional. Read cell by cell, the table lets `prefer-incoming` adopt a fetched incoming body over an item that holds none. Only the prose line "No policy chooses between a body and one nobody has read" still forbids that. Severity: weakened.

- **o05-L357-s1 with o07-L492-s1.** Base (§5): "No policy pushes over a body nobody has read." Base (§7, under `Remove`): "A diverging body not fetched yet (`conflict_object` `NULL`) is named by no resolution, so no `Remove` settles that conflict before the upgrade has read it (§6), and a base never pairs the observed revision with the old body." Rewrite (§5): "No policy pushes over a body nobody has read, and no base pairs the observed revision with the old body." Change: in the base, this clause was the tail of a "so" consequence about a `Remove` resolution, which the preamble makes informative. The rewrite turns it into a bare statement in §5 that binds every policy, the upgrade and the rekey. It is probably true everywhere, but it is a new binding statement no vector checks, and it changes the scope of the §5 sentence. Severity: added.

- **o05-L348-s2 (table A, row "an equal body").** Base: "So is a member carrying, at a revision its base does not hold, the very body the placement holds over that base: whatever the policy, the binding adopts the listed revision and that body as its base, nothing is recorded, pushed or reported". Rewrite: "| an equal body: a member carrying, at a revision its base does not hold, the very body the placement holds over that base | the binding adopts the listed revision and that body as its base; nothing is recorded, pushed or reported | same | same | same |". Change: the base said "So is [no divergence]", which made this case override the both-changed case. The row drops that wording, and table A states no rule for which row wins, so the case also matches row "both changed, body carried" ("the policy (above)"). Severity: wording.

- **n05-A-nobody (table A, row "no body held").** Base: "A placement holding no body (a pull having emptied it) owes nothing until the upgrade refetches it." and "A placement holding no body has nothing to keep and pulls as any." Rewrite: "| no body held | owes nothing (above) | same | same | pulls as any (above) |". Change: putting "owes nothing" opposite "pulls as any" in one row suggests that under `Manual`, `PreferRemote` and `PreferLocal` a placement with no body does not pull on a remote change. In the base it owes no push and still pulls (row 1). Severity: wording.

- **o06-L453-s3.** Base: "only from a row that agrees with the placement's summary, the one the source served, as STORAGE §9 says: on `subject`, `date` and `sender`, compared byte for byte, `NULL` matching `NULL`, and on `size` where the placement states one, against the body's octets." Rewrite: "only from a row that agrees with the placement's summary, the one the source served, as a hint's row does (above), and on `size` where the placement states one, against the body's octets." Change: the referent (o06-L429-s1) also carries "For mail" and "with a retained row on `size` too where both state one, its body becoming the member's unread as a link's does (below)". The pointer therefore imports a second size test on retained rows, plus a back-reference loop, that the base link rule did not have. The practical effect is small: summary size is normally the octets. Severity: changed.

- **o10-L620 bullet vs table D (mutation row, Load).** Base: "A `Copy` or a `Move` also loads its target for the identity it carries into it, and the sources syncing the target, those holding a binding or a checkpoint there, for a placement holding no body (§7)." Rewrite, table D: "| mutation | its placement, or the link id's holders |". Change: the Load cell is narrower than the prose bullet, which is kept above it, so the two disagree for `Copy` and `Move`. Severity: wording.

- **o10-L628-s5 (table D, upgrade row).** Base: "an upgrade settling a conflict under `PreferLocal` states `Overrule` before the upsert adopting the fetched body (§6)". Rewrite: "one settling a conflict under `PreferLocal` states `Overrule` before the upsert adopting the fetched body". Change: none. The base inconsistency with §6 (o06-L471-s1, "under `PreferLocal` or `KeepLocal`") is carried word for word, as the ledger says. It is listed here so the owner still sees it. Severity: wording.

## The three MUSTs (109 to 106)

Raw MUST tokens fall from 16 to 13 in §7. §6 also loses one and §9 gains one: that is o06-L475-s1, moved into table B with its MUST intact. The three missing MUSTs are o07-L489-s1 (the `Remove` refusal on `if_match`) and the two refusals of o07-L490-s1 (`Remove` meeting a conflict without a matching `resolves`, and `Remove` stating `resolves` while meeting none). Each now shares the sentence of its `Edit` twin: "An `Edit` or a `Remove` carrying `if_match` ... MUST be refused" and "An `Edit` without `overrule`, or a `Remove`, ... it MUST be refused ... it MUST be refused the same way". The conditions, the scope (the `Remove` subject) and the level are unchanged in all three merges: kept.

## Counts

- lost: 0
- weakened: 1
- changed: 2
- added: 1
- wording: 4

## Checked and sound

- §2: o02-L64-s1.
- §3: o03-L104-s1 to s2, o03-L106-s1.
- §4: o04-L151-s1 to s6, o04-L153-s1 to s5, o04-L155-s1 to s2, o04-L165-s2 to s3, o04-L205-s1, o04-L206-s1, o04-L207-s1.
- §5: o05-L332-s1 to s3, o05-L334-s1 to s3, o05-L336-s1, o05-L338-s3, o05-L342-s1 to s4, o05-L344-s1, o05-L346-s1, o05-L348-s1, o05-L350-s1, o05-L352-s1 to o05-L355-s1, o05-L359-s1, o05-L402-s1 to o05-L417-s1 (events table, every row), n05-A-caption, n05-A-bothbody, n05-A-tombstone, n05-A-arrival, n05-A-forbidden.
- §6: o06-L423-s1, o06-L425-s2, o06-L427-s1, o06-L429-s1 to s3, o06-L431-s1 to s2, o06-L433-s1, o06-L453-s1 to s2 and s4, o06-L455-s1 to s3, o06-L457-s1 to s2, o06-L459-s1, o06-L461-s1, o06-L469-s1 to o06-L471-s1.
- §7: o07-L480-s1 to o07-L513-s1, the three judgement cuts included. o07-L486 is a "so" consequence of the stated set formula. o07-L508 is advice that the refusal already implies.
- §8: o08-L524-s1 to o08-L556-s2. The cut o08-L556-s2 is restated by "in the transaction that applies it". "Every drop preceding every upsert" covers the `Deleted` drops in §8 as in the base, and table D's rekey row orders them explicitly.
- §9: o09-L570-s1 to o09-L583-s2 (table B rows other than the one above), o09-L593-s1 to o09-L602-s3, n09-B-caption.
- §10: o10-L628-s1 to s4, the s5 cells other than the two above, n10-D-caption, n10-D-upgrade, n10-D-delta, n10-D-head, n10-D-lastpage, n10-D-rekey, o10-L632-s1 to s3.
