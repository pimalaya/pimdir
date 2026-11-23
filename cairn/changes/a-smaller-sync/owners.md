# Owner map

Step 1 of design.md §5.4, made on 2026-11-23 from sync-base.md (SYNC.md at fb56c83). Ids are rules.tsv's `old_id`. For each family: the owning section and the paragraph holding its main sentence, then every other row of the family marked `owner` (a sentence of the owner paragraph, stays), `dup` (an exact restatement, can become a pointer) or `nuance: "<clause>"` (the clause only that row carries: it moves into the owner's sentence or the row stays). "Also" lists rows of other families carrying a clause of this one. A family split between sections by design.md §1.3 names each part's owner. "X to Y" covers every row between the two in rules.tsv order. The label lead-ins heading an owner paragraph (o03-L110-s1, o03-L112-s1, o03-L114-s1, o04-L177-s1, o05-L264-s1, o05-L282-s1, o05-L311-s1, o05-L361-s1, o06-L453-s1, o06-L469-s1) are owner rows, kept verbatim by leadins.txt.

## F1 A delivered create

Owner: §5, o05-L386-s2 (**A delivered create waits for its arrival**): waits, held, reported, given up. Parts: §4 what records it (o04-L216-s3, o04-L203-s1, o04-L204-s1), §6 landing (o06-L437-s3), §7 mutations on it (o07-L495-s1, o07-L515-s1 to o07-L520-s1).

- o02-L58-s1 nuance: "holding a base naming nothing, no flag set, revision nor body" (the binding's shape, said nowhere else); "a pending create a listing can land (§6)"; "before any listing named the member". The definition stays in §2.
- o02-L87-s2 nuance: "which the owner stages on a person's request, as it evicts (STORAGE §11.3)".
- o04-L203-s1 owner (§4 part). Only here: "when a listing can land it (§6)"; "A delete leaves it pending, the target holding the identity under another binding or none"; "A create since landed, withdrawn or delivered is left as it stands"; the MAY "An owner whose consumer stages mutations while a push is in flight MAY record the create delivered before the relocation leaves"; "a delivered create stays its tombstone's destination (§3), so a relocation that never went is pushed again".
- o04-L204-s1 owner (§4 part). Only here: "pending or delivered, whether or not a listing could land it (§6)"; "its base set to the flags and body staged on the create and to the revision the outcome states"; "It is never left delivered for a listing to land"; "The landing reports nothing, the relocation being the consumer's (§5)"; "one whose stated handle this source already binds in `to` is recorded delivered as without one".
- o04-L216-s1 owner (heading).
- o04-L216-s2 owner: "(an IMAP `APPEND` on a server without UIDPLUS, RFC 4315)" is an example.
- o04-L216-s3 owner. Only here: "its provisional binding, staged body and flags kept, no `Superseded` drop written and no `Created` reported".
- o04-L216-s4 nuance: "A create no listing can land (§6) is left pending instead, and MUST NOT be pushed again in that run" (the only per-run push bar).
- o04-L218-s1 dup (of o05-L328-s3 and o06-L437-s2: "as for an add whose record was lost" is o06-L437-s2's "by an accepted add whose record was lost").
- o05-L296-s2 nuance: "nor counted among the based bindings below" (not counted by the guards; o05-L386-s4 says only "No absence finds it").
- o05-L328-s1 to o05-L328-s3: the pending create's wait, its own rule (F1-adjacent), owner of "creates wait". o05-L328-s2 nuance: "a head's write included, nor in a delta before its members are named".
- o05-L386-s1 dup (of o02-L58-s1 and o04-L203-s1).
- o05-L386-s3 owner. Only here: "the delete or the relocation being **held** for that page, never withdrawn".
- o05-L386-s4 owner: "no run drops it but the one landing it" (inconsistent with `Abandon`, design.md §5.4, carried unchanged).
- o05-L388-s1 nuance: "or under another binding when the source deleted rather than relocated (§4)".
- o05-L388-s2 nuance: the SHOULD "An engine SHOULD report every delivered create its run holds while it waits".
- o05-L390-s1 to o05-L390-s3 owner. Only here: "and what was staged on it with it"; "no count of runs"; "reported by its handle".
- o05-L392-s1 nuance: "a tombstone included, and the run pushes what it owes against the handle it landed on".
- o05-L394-s3 nuance: "supersedes the provisional handle in the same batch"; "(one assigned none is delivered, §4)" is dup.
- o06-L437-s1 owner (§6 part, heading).
- o06-L437-s2 owner (§6 part). Only here: "keyed by the hint or by the hint minted over the provisional handle it derives (§7), the bare key first"; "or by another client".
- o06-L437-s3 owner (§6 part). Only here: "only a hint held by a based binding of this source other than a delivered create ... is minted".
- o06-L439-s1 nuance: "the base set to the flags the listing or the fetch reported and, for an immutable kind, to the staged body".
- o06-L439-s2 nuance: "relocating into the destination the store derives for it then (§3), if any: one whose destination landed first (another client restored it) derives none, and its `Remove` is a delete".
- o06-L441-s1 nuance: "For a mutable kind the base takes the listed revision, and the body when the listing or the fetch carried one".
- o06-L441-s2 nuance: "A carried body equal to the staged one settles the create".
- o06-L443-s2 nuance: "the listed revision is one its base does not name, so ... it is a remote edit over the tombstone, which revives it".
- o06-L443-s3 nuance: "its staged `Remove` is not pushed: ... the person's to stage again once the upgrade has".
- o06-L463-s3 nuance: "so no upgrade fetches it"; the wait itself is dup.
- o07-L495-s1 owner (§7 part). Only here: "it withdraws nothing ... binding and base kept".
- o07-L515-s1 owner (§7 part): "never by a rule of the engine's or a connector's".
- o07-L516-s1 owner: the refusal on any other placement.
- o07-L517-s1 owner. Only here: "holding its body, its summary and the flags staged on it"; "A `Remove` or a relocation held on it (§5) is given up with the binding".
- o07-L518-s1 owner. Only here: "Giving up a create is deleting the item it created, on every source that took it".
- o07-L519-s1 owner: "It pushes nothing"; the event is dup of o05-L411-s1.
- o07-L520-s1 owner: "A member arriving later under that identity revives the retained row, or joins a tombstone still propagating".
- o08-L538-s2 nuance: "which no rekey finds absent nor counts; one a member resolves to is carried onto it as a page lands it (§6)".
- Also: o03-L110-s2 nuance "(a delivered create names no member to copy from)"; o03-L114-s2 nuance "or a delivered one"; o05-L407-s1 nuance "or, delivered, goes on waiting"; o05-L411-s1 (the event); o06-L431-s2 nuance "a delivered one goes on waiting"; o07-L506-s1 nuance "A `Move` of a delivered create tombstones it as a `Remove` does, its relocation held the same way"; o10-L628-s3 nuance "the relocation's naming its destination's collection"; o11-L660-s1 "a delivered create an `Abandon` gave up".

## F2 No body pushed over, or chosen against, a body nobody has read

Owner: §5 for the source's axis, o05-L357-s2 (with o05-L340-s2 for the `Update`); §9 for the item's, o09-L590-s1. design.md §5.4 step 4: §6 "item conflict revisited" (o06-L473-s1) and §9 **A body not held.** are one rule from two ends, one agent.

- o03-L101-s1 nuance: "(a base naming no body differs from every body). A placement holding no body owes no body, whatever its base names".
- o05-L338-s4 nuance: "A member carrying none drops the local body and lowers the level to `Meta`".
- o05-L340-s1 nuance: "owes nothing until the upgrade refetches it".
- o05-L340-s2 owner (§5). Only here: "nor the `Remove` a move's staged edit rides ahead of".
- o05-L340-s3 nuance: "after which the local body is an edit over a body read".
- o05-L357-s1 owner (§5): the summary sentence.
- o06-L443-s1 nuance: "An arrival carrying no body is that case as well ... the engine MUST NOT push the staged body over it" (the landing's own MUST NOT; keep).
- o06-L445-s1 nuance: "the base at that revision naming no body, and reported `Conflicted` beside the `Created` of the landing" ("Whatever the source's policy ... as `Manual` records a divergence" is dup of o05-L357-s2).
- o06-L447-s1 dup.
- o06-L447-s2 nuance: "It clears the conflict when it equals the staged one"; "`PreferRemote`'s dropped body and the server body `PreferLocal` pushes over kept and reported" (names `PreferLocal` alone, as o10-L628-s5 does, where o06-L471-s1 names `PreferLocal` or `KeepLocal`).
- o06-L447-s3 dup (of o09-L590-s1's last sentence).
- o06-L447-s4 nuance: "The flags and body staged on the create stay, so an edit made on it still pushes".
- o06-L473-s1 nuance: "is revisited by the upgrade of every binding of the item whose base names a revision and no body".
- o06-L473-s2 nuance: "the binding takes that body as its base and its `shared_object`".
- o06-L473-s3 dup (of o09-L591-s1).
- o06-L475-s1 nuance: the MUST "under `manual` it MUST land in `items.conflict_object`, never in the item's own object".
- o06-L476-s1 nuance: "one holding none waits, recorded as `manual` records it, for the fill that reads its own (§9)".
- o07-L492-s1 nuance: "so no `Remove` settles that conflict before the upgrade has read it (§6), and a base never pairs the observed revision with the old body".
- o07-L504-s1 nuance: the MUST "An overruling `Edit` MUST be refused, staging nothing, when the conflict it settles holds no diverging body"; "On a placement and an item in no conflict it keeps nothing".
- o09-L587-s1 to o09-L587-s4 owner (§9). o09-L587-s2: "has changed for every binding whose `shared_object`, or the sync base it falls back to, names one"; o09-L587-s3: "An upsert carrying no body over an item holding one disagrees with it".
- o09-L589-s1 owner: the fill, "An item conflict standing stays, its `conflict_object` kept, until the policy settles it".
- o09-L590-s1 owner (§9).
- o09-L591-s1 owner: "keyed over the handle of the binding whose upgrade fetched it or whose upsert filled the item".
- Also: o05-L353-s1 nuance "A member carrying no body is pulled as any pull is, the item emptied for the upgrade to fetch: nothing is written to the remote, and the local edit is kept"; o05-L355-s1 nuance "A placement holding no body has nothing to keep and pulls as any"; o06-L463-s2 nuance "`Full` holding a local body over a base naming a revision and no body, whose push waits for that base"; o07-L498-s1 nuance "A conflict whose diverging body nobody has read (`conflict_object` `NULL`) is named by no resolution"; o11-L660-s1 "no body is pushed over, nor left facing, a server edit nobody has read".

## F3 A refusal

Owner: §5, o05-L396-s2 (**A refused change is held.**); §4 for the connector's classification, o04-L213-s1 and o04-L214-s1.

- o02-L74-s1 nuance: "its reason, the change's key and when, which holds that change" (the definition stays).
- o04-L210-s1, o04-L210-s2 owner (§4): "or leaves it unreported".
- o04-L212-s1 owner (§4): "which a later listing moves past".
- o04-L213-s1 owner (§4). Only here: the status list "from 400 to 499 but 401, 407, 408, 409, 412, 423, 425 and 429"; "`reason` is the text the remote gave, which the engine records once scrubbed (STORAGE §18)".
- o04-L214-s1 owner (§4). Only here: "A connector that cannot tell a refusal from a stale base MUST answer `Rejected`"; the unreported list (transport, 401/407, 423, quota).
- o05-L396-s1 owner (lead-in).
- o05-L396-s3 owner: "neither dropped nor reverted, for as long as that refusal stands".
- o05-L396-s4 owner: "its own outcome replaces or clears the refusal".
- o05-L398-s1 owner: `ClearRefusal`.
- o05-L398-s2 owner: "a create withdrawn (§7) or landed (§6), a member dropped, a handle a rekey renumbered".
- o05-L398-s3 owner: the refused offered create upserted "under the provisional handle it was pushed under, with no base and the item's flags and body, before the `RefusePlacement`".
- o05-L398-s4 owner: "withdrawn by a `Remove` or with the item's delete (§3, §7), and pushed again once its key changes".
- o10-L626-s1 nuance: "a refused binding owes a push, so every load deriving one loads it".
- Also: o05-L373-s5 nuance "A rejected or a refused push is pending like any other and follows no policy"; o05-L394-s4 dup "`Rejected`, `Refused` or unreported leaves it pending"; o05-L413-s1 nuance "A held change's is reported with the write after its merge, which records it as standing"; o09-L612-s1 nuance "a target's refusal reported as a refused or a rejected push"; o10-L628-s3 nuance "after the upsert binding a create the store offered (§5)"; o12-L671-s1 "a refusal's reason" (STORAGE §18).

## F4 What a listing's absence proves

Owner: §5, o05-L264-s2 (**Which absences delete.**), as table C. §4 keeps the connector's flags (o04-L128-s1 to o04-L136-s1).

- o02-L69-s1 nuance: "and the only place its absence means anything (§5). Mail only".
- o04-L128-s1 nuance: "save what a narrowing filter cannot list and what a cap leaves out" (absent from o04-L136-s2, see the findings).
- o04-L132-s1, o04-L133-s1, o04-L134-s1 owner (§4 page fields table): "optionally" (on `enumerated`).
- o04-L136-s1 owner (§4): "MUST set `complete` only on a page of a round".
- o04-L138-s3 owner (§4): "one a listing, a fresh delta or an enumeration it started again did not return".
- o04-L181-s1 nuance: "a listing by date states no removal and proves none by an absence".
- o05-L248-s3 owner (scope): "or when it has no usable `date`".
- o05-L252-s1 owner: "a margin of two days below `since`".
- o05-L252-s2 owner: "a margin of one day".
- o05-L254-s1 to o05-L254-s5 owner (connector side, §5). o05-L254-s5 only here: the SHOULD "on a band round's last page as on any other".
- o05-L256-s1 to o05-L256-s3 owner: "by the source stating it or by its configuration".
- o05-L258-s1 owner: "the engine filters no page by date and names every member a page carries".
- o05-L260-s1, o05-L260-s2 owner: "MUST NOT be dropped, pulled or pushed on the evidence of its absence".
- o05-L264-s3 owner: "every other source binding it then projects a `Tombstone` and pushes its `Remove` (§9)".
- o05-L266-s1 owner: the list of non-absences (table C's rows).
- o05-L270-s1 owner: "A scope, a narrowing, a widening, an eviction (STORAGE §11.3) ... derive none".
- o05-L270-s2 owner: "never back to that remote".
- o05-L288-s1, o05-L288-s2 owner: "every based binding of this source the round did not stamp"; "or is unknown and the round is no band round".
- o05-L288-s3 pointer.
- o05-L290-s1 dup (of o05-L288-s2's band clause; keep the MUST NOT as a row of table C).
- o05-L290-s2 nuance: "Undated members are reconciled by rounds over a whole scope and by deltas".
- o05-L292-s1 to o05-L292-s5 owner. o05-L292-s3: "whatever its `date`"; o05-L292-s4: "for a stated removal, an unnarrowed round or a later enumeration to decide"; o05-L292-s5: the unlisted count.
- o05-L294-s1 to o05-L294-s3 owner: the unlisted count "as a narrowed round handing no enumeration does".
- o05-L296-s1 nuance: "A round resumed from the store and one the run opened MUST infer the same deletes".
- Also: o04-L138-s4 (F15) nuance "the connector answers a round instead, handing `enumerated` where a filter narrowed it, and the absence is found in scope, counted and parked as any other"; o05-L367-s1 nuance "unless its placement holds a body its base does not"; o05-L324-s1 (F5) "infers no delete from an absence"; o05-L322-s1 (F5) "the rest being found absent"; o08-L542-s2 (F7); o09-L606-s1 nuance "This is how an absence a closed round found (§5) reaches every other source, and the only way"; o10-L623-s1 "is counted over every based binding of the source in its scope"; o11-L660-s1.

## F5 Heads

Owner: §4 for the connector, o04-L177-s2 (**Heads.**); §5 for the engine, o05-L311-s2 (**Heads.**).

- o02-L68-s1 nuance: "so what arrives during a long round shows before it closes"; "A **delta head** lists from the round's checkpoint" (o05-L313-s1 adds the band round's source checkpoint).
- o04-L177-s3 owner (§4): "checked against the scope as a delta is".
- o04-L177-s4 owner (§4): "never moves the round's".
- o04-L179-s1 owner (§4): "which it MUST carry"; "A source whose checkpoint arrives only with a round's last page has none to list from before that round closes".
- o04-L180-s1 owner (§4): "less a margin of two days"; "never moves back".
- o04-L181-s1 owner (§4; F4 clause).
- o04-L183-s1 note.
- o04-L185-s1 to o04-L185-s3 owner (§4): "One that cannot list the head it is asked for at all ... answers none".
- o04-L187-s1 owner (§4): "read no earlier than the checkpoint that page carries".
- o04-L189-s1 to o04-L189-s3 owner (§4): "leaves out a member the source no longer holds in the collection".
- o05-L311-s3, o05-L313-s1 to o05-L315-s1 owner (§5): "for a band round, which carries none of its own, from the source's checkpoint".
- o05-L317-s1 owner: "not the band a band round lists".
- o05-L319-s1 nuance: "a vanished handle dropped at once, whatever its date".
- o05-L319-s2 nuance: "It lands in the write after the chunks of its pushes".
- o05-L321-s1 nuance: "`SetRoundCursor` with no cursor, the page's staying"; "the next head's, or the next delta's once the round closes on that checkpoint".
- o05-L322-s1 nuance: "A member it named is decided by the last page".
- o05-L324-s1 nuance: "derives no `Add` (creates wait for the round's last page, below)".
- o05-L324-s2 nuance: "one member under one handle, refreshed as any listed member is".
- o05-L324-s3 nuance: "lists it present again".
- o05-L326-s1 nuance: "never a band: the checkpoint the round would close with is void".
- Also: o05-L276-s1 (F9) "listing the round's head first (below)" (binds, against o05-L311-s2's SHOULD, see the findings); o04-L173-s2 (F9) "caught by the round's next head"; o05-L280-s3 "a head alone moving it"; o05-L305-s2 "none of its pages nor heads listing one"; o05-L328-s2 "a head's write included"; o10-L624-s1 the head's load; o10-L628-s2 "(a head's carrying no cursor, so the one a page landed stays)"; o11-L647-s1 "(a head not counted)".

## F6 The conflict policies

Owner: §5 for the source's, o05-L350-s1 (**Conflict policy**), as table A; §9 for the collection's, o09-L576-s1, as table B.

- o04-L165-s2 dup ("both is a conflict under the source's policy"); "pushed as an `Update` gated on the base ETag" is §4's own.
- o04-L165-s3 nuance: "Under `Manual` a person keeps both (the local body saved as a new file with an `Add`, before an `Edit` adopts the server's) or picks one with an `Edit`".
- o05-L338-s3 nuance: "the member's meta becomes the summary, address rows and sort key".
- o05-L342-s1 owner (table A row "both changed"): "when the local body is the binding's own".
- o05-L342-s2 owner (row "a fold").
- o05-L342-s3 owner.
- o05-L344-s1 owner (row "conflict meeting a newer revision").
- o05-L346-s1 owner: "reported as `Conflicted`".
- o05-L348-s1, o05-L348-s2 owner (row "an equal body"): "nothing is recorded, pushed or reported".
- o05-L352-s1 to o05-L355-s1 owner (table A columns). o05-L354-s1 only here: "In a write that commits before the push"; "A push rejected, interrupted or replayed finds the body kept and the base moved, so nothing is kept twice". o05-L355-s1 only here: "a change made on that remote alone is never pulled".
- o05-L359-s1 pointer.
- o06-L469-s2, o06-L469-s3 owner (§6 part, "a body read later by the upgrade").
- o06-L471-s1 nuance: "content pushes allowed"; "so the next sync pushes the local body gated on that revision".
- o09-L570-s1 to o09-L574-s1 owner (§9): "not the base the upsert carries, and always when it bound none of the item before it".
- o09-L578-s1, o09-L579-s1 owner (table B).
- o09-L581-s1, o09-L581-s2 owner.
- Also: o03-L99-s1 (status `Conflict`); o05-L357-s2 (F2); o05-L369-s1 "a tombstone also holding a local edit is the both-changed case and follows the policy"; o07-L502-s1 to o07-L505-s1 (F14); o08-L550-s2 "or as a `Conflict` at the fetched revision when it also holds a local edit"; o10-L628-s5 "an upgrade settling a conflict under `PreferLocal`".

## F7 The absence guards

Owner: §5, o05-L303-s2 (**A mass absence parks.**), as table C's guard column; §8 keeps what differs for a rekey (o08-L540-s2, o08-L542-s3).

- o05-L303-s1 owner.
- o05-L305-s1, o05-L305-s2 owner: "none of its pages nor heads listing one so that no binding carries its id once its last page lands"; "whatever their number".
- o05-L307-s1, o05-L307-s2 owner: "the checkpoint it carries recorded with no cursor, `SetRoundCursor`"; "with the absent and the bound counts".
- o05-L309-s1, o05-L309-s2 owner: "A later run resumes it from its first page, the round holding no cursor, and decides again".
- o08-L540-s1, o08-L540-s2 owner (§8): "resolving to no member".
- o08-L540-s3 nuance: "the whole collection being its scope and a binding absent when no member resolves to its link id".
- o08-L540-s4 dup (of o05-L305-s2, on a rekey).
- o08-L542-s1 to o08-L542-s4 owner (§8). Only here: "it can be neither dropped as gone nor carried as it is"; "which drops each such binding `Deleted` as an unresolved one is"; "A capped rekey every based binding resolves in is written as any other".
- o08-L544-s1 nuance: "leaves the checkpoint and the generation unmoved".
- o08-L544-s2 nuance: "the next run meets the moved space again and names the rekey again".
- Also: o04-L138-s4 "no guard counts it"; o05-L266-s1 "nor a round the guards below park"; o05-L276-s1 "(a parked round, below)"; o05-L415-s1 the parked report; o10-L623-s1; o11-L660-s1.

## F8 Which write op a verb emits

Owner: each rule's own section; §10 holds table D, which replaces o10-L628-s2 to o10-L628-s5 and adds nothing.

- o10-L628-s1 owner: "Every verb ends in a batch".
- o10-L628-s2 nuance: "`OpenRound` first in its first page's batch" (only §10 says first); "`SetCoverage` beside a delta's checkpoint".
- o10-L628-s3 nuance: "the relocation's naming its destination's collection"; "naming that collection too"; "after the upsert binding a create the store offered".
- o10-L628-s4 dup (of o07-L517-s1).
- o10-L628-s5 nuance: "states `Overrule` before its upsert"; "an `Edit` or a `Remove` states `Settle` when its `resolves` names the item's conflict"; "an upgrade settling a conflict under `PreferLocal` states `Overrule` before the upsert adopting the fetched body" (`PreferLocal` alone, design.md §5.4).
- Inline statements table D copies (rows of other families): o04-L203-s1 `DeliverPlacement`; o04-L204-s1 `LandPlacement`; o04-L216-s3 `DeliverPlacement`; o05-L278-s1 `SetCoverage`; o05-L280-s2 and o05-L282-s2 `OpenRound`; o05-L282-s3 `Stamp`, `SetRoundCursor`; o05-L298-s1 `CloseRound`; o05-L307-s2 `SetRoundCursor`; o05-L321-s1 `Stamp`, `SetRoundCursor`; o05-L396-s2 `RefusePlacement`; o05-L398-s1 `ClearRefusal`; o05-L398-s3 the upsert before `RefusePlacement`; o07-L493-s1 and o07-L505-s1 `Settle`, `Overrule`; o07-L517-s1 the `Deleted` drop; o08-L532-s1, o08-L532-s2 `Rekeyed`, "every drop preceding every upsert"; o10-L630-s1 "A batch is cut between candidates, never inside one, and a rekey is never cut".

## F9 Rounds, stamps, checkpoints

Owner: §5, o05-L282-s2 (**Rounds.**); §4 for what a connector hands (o04-L136-s2, o04-L173-s1).

- o02-L65-s1, o02-L66-s1, o02-L67-s1, o02-L70-s1, o02-L71-s1: definitions, stay in §2. o02-L66-s1 nuance: "under an id drawn when it opens. It stamps the bindings it lists".
- o04-L129-s1 to o04-L131-s1 owner (§4 page fields table).
- o04-L136-s2 owner (§4): "every member of the scope listed across the round's pages" (no narrowing or cap exception, see the findings).
- o04-L140-s1 owner (§4): "the run fails before that page's write, and the round stays open as the pages before it left it".
- o04-L171-s1, o04-L171-s2 owner (§4): "rather than answer from the beginning as if it resumed".
- o04-L173-s1 to o04-L173-s3 owner (§4): "that checkpoint covers the round itself".
- o04-L175-s1 owner (§4): "bound to the scope".
- o05-L274-s1 to o05-L278-s1 owner (choosing the listing). o05-L276-s1: "the round lists a band exactly when the run would"; o05-L277-s1: "(no coverage, a checkpoint held without one included)".
- o05-L280-s1 to o05-L280-s3 owner (band round): "when that band adjoins the coverage"; "Its listing need carry no undated member".
- o05-L282-s3 owner: "whether a member moved or not".
- o05-L284-s1, o05-L284-s2 owner: "so the abandoned listing's stamps protect nothing ... (a relisting, no fetch)".
- o05-L286-s1 owner.
- o05-L298-s1, o05-L300-s1, o05-L301-s1 owner: "else the latest a head or an earlier page landed, the old one kept when it carries none"; "for a band round the span of the band and the coverage it adjoins, stamped with the instant".
- o05-L400-s2 owner (push discipline): "in no earlier one".
- o05-L400-s3 nuance: "A page's cursor and the checkpoint an open round carries are not the source's checkpoint".
- o08-L556-s1 nuance: "leaves the coverage as it was".
- o10-L630-s2 dup ("The checkpoint is per source and lands last (§5)").
- Also: o04-L144-s1 the rekey naming; o04-L232-s2 and o04-L234-s1 (keys forgotten once "the checkpoint after their chunk has landed"); o05-L307-s2; o05-L321-s1; o05-L326-s1.

## F10 Another message under one Message-ID

Owner: §6, o06-L429-s2; §4 for the connector's raw read (o04-L153-s3); §10 for the write enforcing it (o10-L632-s3).

- o02-L64-s1 nuance: "which it keeps while the content stays"; "opaque, and comparable only between bindings of one source".
- o04-L151-s1 to o04-L151-s5 owner (§4, server object id). o04-L151-s4 only here: "a listing naming the member stating none clears it, a fetch stating none leaves it". o04-L151-s5: "in one account".
- o04-L151-s6 pointer.
- o04-L153-s1 to o04-L153-s5 owner (§4). Only here: "at least for every member whose decoded summary disagrees with a row holding its hint"; "reading every member raw always meets this".
- o04-L155-s1, o04-L155-s2 owner (§4): "a missed dedup, which the engine reports where the row is this source's own create (§5)".
- o06-L425-s2 nuance: "minted again over a held key"; "when this source already binds the hint under another handle".
- o06-L429-s1 owner: "`NULL` matching `NULL`, and with a retained row on `size` too where both state one, its body becoming the member's unread as a link's does".
- o06-L429-s3 nuance: "A step whose load cannot see that row leaves it to the write".
- o06-L431-s1 reason.
- o06-L431-s2 owner (§6): the `Disagreed` MUST; "a pending one is pushed beside the member".
- o06-L433-s1 nuance: "draws a `seq` of its own (STORAGE §9.1) and links none of its body".
- o06-L453-s2 to o06-L453-s4 owner (linking): "the server object id the run's source states on its binding of that row"; "on `size` where the placement states one, against the body's octets".
- o06-L455-s1 to o06-L455-s3 owner: "whatever the summaries agree on".
- o06-L457-s1 nuance: "a placement stating none is linked on the three alone"; o06-L457-s2 nuance: "A row holding no summary agrees with nothing".
- o06-L459-s1 nuance: "links only where the two happen to agree".
- o06-L461-s1 nuance: "one under a writer-derived key MUST be fetched, never linked".
- o09-L583-s2 dup (pointer to §6).
- o10-L632-s1 to o10-L632-s3 owner (§10): "an engine whose load showed the row mints the member the same way first, so both name it alike".
- Also: o05-L407-s1 (F16) "a decoded summary among the causes (§4)"; o06-L437-s3 "or by an item whose summary names another message"; o06-L437-s4 "another message reusing its `Message-ID` in the target among them"; o07-L509-s1 "a message that does not agree with it, minted beside it"; o07-L513-s1 "a message agreeing with neither is minted instead"; o07-L520-s1 "agreeing with it"; o11-L660-s1.

## F11 Supersessions

Owner: §3, o03-L112-s2 (**Superseded.**) for what the placement names; §5, o05-L363-s1 for the held tombstone; §4, o04-L196-s1 for the connector.

- o03-L112-s3 owner: "Unlike an origin it holds whatever body".
- o04-L197-s1 owner (§4): "`405`, `501`, or a `404` for the member it binds"; "One refusing it for the member's identity rejects the change".
- o04-L202-s1 nuance: "a create delivered by a move (`Add`) takes the member it supersedes along".
- o04-L230-s1 nuance (key): "`supersedes` is not part of it".
- o05-L363-s2 nuance: "A remote edit over it still revives it".
- o05-L365-s1 nuance: "no pending create of its identity being left to relocate into".
- o05-L365-s2 dup (of o04-L202-s1).
- Also: o10-L628-s3 "`Superseded` for a provisional handle an accepted add or a landed arrival replaced" (the drop reason, another meaning); o11-L654-s1 `supersessions`.

## F12 Move and relocation

Owner: §5, o05-L380-s1 (**A move**); §3 for origin and destination (o03-L110-s2, o03-L114-s2); §4 for the connector (o04-L198-s1); §7 for `Copy` and `Move` (o07-L506-s1).

- o02-L60-s1, o02-L61-s1 definitions (stay). o02-L61-s1 says "a pending create" where o03-L114-s2 adds "or a delivered one".
- o02-L84-s1, o02-L85-s1 definitions (stay): "and `Add` for a create no relocation delivered".
- o03-L110-s3 owner.
- o03-L116-s1, o03-L116-s2 owner: "The bare key MUST be preferred".
- o03-L118-s1 owner: "so both read the same after a crash and after another source's write folded the item".
- o04-L200-s1 owner (§4): "MUST be absent when its destination is a create under a minted key".
- o04-L201-s1 owner (§4).
- o05-L361-s2 dup (of o03-L114-s2).
- o05-L371-s1, o05-L371-s2 nuance: "abandoned rather than half-applied: the member stays in the source, live and clean at the pushed revision, and the consumer restages the move".
- o05-L380-s2 owner: "An engine MUST NOT drop either half for the other".
- o05-L382-s1 owner.
- o05-L382-s2 dup (of o04-L201-s1).
- o05-L382-s3 nuance: "a copy the target held before the move not being that delivery".
- o05-L382-s4 nuance: "A create landed first, by its copy from the origin, leaves no destination".
- o05-L384-s1 dup (of o04-L204-s1).
- o05-L384-s2 dup.
- o06-L437-s4 nuance: "A create a relocation landed on the handle it stated (§4) is such a binding".
- o06-L437-s5 nuance: "is landed by no listing: no source states such a key".
- o07-L506-s1 owner (§7).
- o07-L507-s1 owner (§7): "A queued `move` so parks".
- o07-L508-s1 owner (§7): "staging nothing in either collection"; "A `Copy` meets none".
- o07-L509-s1 owner (§7): "a tombstoned or retained holder blocks nothing".
- o07-L510-s1 owner (§7): "unless its binding is based and its source syncs the target, holding a binding or a checkpoint there".
- o07-L522-s1, o07-L522-s2 owner (§7): the trash advice, unmarked, binds (design.md §5.4).
- Also: o04-L199-s1 "MUST take it out of that collection alone while the source holds it in another"; o04-L203-s1 and o04-L204-s1 (F1); o05-L340-s2 "nor the `Remove` a move's staged edit rides ahead of"; o05-L363-s1 "nor the `Update` a move's staged edit rides ahead on"; o06-L439-s2; o07-L501-s1 "the destination its tombstone offered no longer derives"; o10-L620-s1 the target's load.

## F13 Flags

Owner: §5, o05-L332-s1 (**The flag axis**); §4 for the wire (o04-L205-s1); §7 for `SetFlags` (o07-L486-s1); §8 for a rekey (o08-L530-s2).

- o03-L104-s1, o03-L104-s2 owner (§3): "An unknown base is no base on the flag axis".
- o04-L206-s1 owner (§4): "(the one the run listed, else the base)".
- o04-L207-s1 owner (§4): "one deriving two empty sets pushes nothing".
- o05-L332-s2, o05-L332-s3 owner.
- o05-L334-s1 to o05-L334-s3 owner: "the flag axis then withholds its push and still merges and writes".
- o05-L336-s1 owner.
- o07-L484-s1 owner (§7): "a `Created`, `Conflict` or `Tombstone` placement keeps its status".
- o07-L485-s1 owner.
- o07-L487-s1 owner: "MUST be refused, staging nothing, when the placement's flags are unknown".
- o08-L530-s1 owner (§8).
- o08-L530-s3 nuance: "the rekey pushes nothing".
- Also: o04-L229-s1 the flag set's key encoding; o09-L562-s2 "A known flag set ... replaces a known one; an unknown one leaves the shared value alone"; o09-L562-s3 "its flags ride along"; o09-L585-s2 "Flags never conflict" (dup of o05-L332-s1).

## F14 Kept bodies and `Overruled`

Owner: §9, o09-L593-s2 (**A policy's loser is kept.**).

- o06-L427-s1 nuance: "is kept as a retained item keyed over the member's handle and reported `Overruled`, never left as the item's body".
- o07-L502-s1 owner (§7 part): "MUST state `overrule`; a person's resolution, which states `resolves`, does not".
- o07-L503-s1 nuance: "the binding's `conflict_object` then the item's"; "before any body the collection's policy keeps in the same write".
- o07-L505-s1 nuance: "No divergence is measured (§9) and nothing is retained or reported"; "The editing binding's `shared_object` moves to that body, every other binding's stays".
- o09-L593-s1, o09-L595-s1 to o09-L598-s1 owner.
- o09-L600-s1 owner: "only a person's resolution may".
- o09-L602-s1 to o09-L602-s3 owner: "the retained body a policy kept before included"; "in the order kept".
- Also: o05-L353-s1, o05-L354-s1, o05-L355-s1 (F6); o05-L410-s1 "or a revive set aside (§6)"; o05-L417-s1 "which any verb whose write kept a body no one asked to lose reports"; o06-L447-s2; o06-L471-s1; o06-L476-s1; o09-L591-s1; o11-L660-s1 "every `Overruled` event's key".

## F15 A stated removal applies whatever the date

Owner: §4, o04-L138-s4 (**A removal is stated, never guessed.**).

- o04-L127-s1 dup.
- o04-L138-s1, o04-L138-s2 owner: "(an IMAP `VANISHED`, a JMAP `destroyed`, a delta's removed entry)".
- o05-L260-s3 dup.
- Also: o05-L290-s2 nuance "a removal the source states applies to them whatever the round"; o05-L292-s4 and o05-L294-s2 "a removal is applied there only when the source states it, a vanished handle" (dup); o05-L319-s1 "a vanished handle dropped at once, whatever its date"; o05-L367-s1 "or a vanished handle".

## F16 Events

Owner: §5, o05-L402-s2 (**Events.**), the ten events as a table.

- o05-L402-s1 owner.
- o05-L404-s1 owner: "per item, in order".
- o05-L406-s1 to o05-L413-s1 owner (table rows). o05-L407-s1 only here: "after its `Added`"; "naming the member by its handle and the create by its link id". o05-L408-s1: "and never one a policy kept apart". o05-L413-s1: "A held change's is reported with the write after its merge".
- o05-L415-s1, o05-L415-s2 owner: "A pushed flag, body or delete reports nothing".
- o05-L417-s1 owner (with the upgrade inconsistency, see the findings).
- o08-L536-s1 nuance: "the rekey's checkpoint lists it no more".
- Also: o04-L204-s1 "The landing reports nothing"; o04-L216-s3 "no `Created` reported"; o05-L346-s1 "reported as `Conflicted`"; o05-L388-s2; o06-L431-s2; o06-L445-s1; o07-L519-s1; o08-L544-s1 "the run reports the rekey parked"; o11-L650-s1 the events a vector names.

## F17 Immutable kind

Owner: §9, o09-L583-s1; §3, o03-L106-s1 for the projection.

- o03-L106-s1 owner (§3): "An immutable kind never owes a body".
- o05-L342-s4 nuance: "Mail reports no revision and never reaches this axis".
- o06-L423-s1 nuance: "a later one MUST NOT re-identify a linked placement of an immutable kind".
- Also: o06-L439-s1 "for an immutable kind, to the staged body, one identity being one message"; o06-L453-s2 "A `Full` upgrade of an immutable kind".

## The table shapes

Fixed before any rewriting (design.md §5.2). Cells are left empty; the rewriters fill them with the wording of the rows they table. The rows of A and C and the columns of all four are design.md's; design.md names eleven cases for A's "thirteen", so both-changed is split by whether the body is carried (o05-L342-s1, o05-L357-s2) and the item's conflict meeting a revision (o05-L346-s1) is a row of its own. The rows of B and D are this lane's proposal, each drawn from the rows that state it.

### A, the source's policy by case (§5)

| Case | `Manual` | `PreferRemote` | `PreferLocal` | `KeepLocal` |
| --- | --- | --- | --- | --- |
| remote changed, body carried | | | | |
| remote changed, no body carried | | | | |
| both changed, body carried | | | | |
| both changed, no body carried | | | | |
| the item's conflict meeting a revision its base does not hold | | | | |
| a fold (a local body another source folded) | | | | |
| an equal body | | | | |
| a conflict meeting a newer revision | | | | |
| a body read later by the upgrade | | | | |
| a tombstone and a remote edit | | | | |
| an arrival landing a create | | | | |
| content pushes forbidden | | | | |
| no body held | | | | |

### B, the collection's policy by case (§9)

| Case | `manual` | `prefer-incoming` | `prefer-existing` |
| --- | --- | --- | --- |
| only the source changed | | | |
| only the item changed | | | |
| all three (a divergence) | | | |
| an immutable kind | | | |
| the incoming body not carried | | | |
| the item holding no body (a fill) | | | |
| the missing body read, equal | | | |
| the missing body read, differing | | | |
| the body not adopted | | | |

### C, what a listing's absence proves (§5)

| Listing | Stated removals | An in-scope dated member unlisted | An undated one | An out-of-scope one | A provisional create | The guard | Closes | Reports |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| delta | | | | | | | | |
| delta head | | | | | | | | |
| band head | | | | | | | | |
| a page before the last | | | | | | | | |
| the last page of a whole-scope round | | | | | | | | |
| a band round | | | | | | | | |
| narrowed, with `enumerated` | | | | | | | | |
| narrowed, without `enumerated` | | | | | | | | |
| capped | | | | | | | | |
| interrupted | | | | | | | | |
| parked | | | | | | | | |
| rekey | | | | | | | | |
| capped rekey | | | | | | | | |

### D, load and write by step (§10)

| Verb and step | The load | The ops, in batch order | The order constraint | The rule's section |
| --- | --- | --- | --- | --- |
| mutation | | | | |
| upgrade | | | | |
| delta | | | | |
| a round's first page | | | | |
| a page before the last | | | | |
| a head | | | | |
| a round's last page, closing | | | | |
| a round's last page, parked | | | | |
| a push chunk | | | | |
| rekey | | | | |
| `Abandon` | | | | |

### §4, the page fields

| Field | On which pages | What it holds | The connector's duty |
| --- | --- | --- | --- |
| `items` | | | |
| `vanished` | | | |
| `complete` | | | |
| `last` | | | |
| `cursor` | | | |
| `checkpoint` | | | |
| `narrowed` | | | |
| `enumerated` | | | |
| `capped` | | | |

### §5, the events

| Event | Reported on | Names |
| --- | --- | --- |
| `Added` | | |
| `Disagreed` | | |
| `FlagsChanged` | | |
| `ContentChanged` | | |
| `Vanished` | | |
| `Conflicted` | | |
| `Overruled` | | |
| `Abandoned` | | |
| `Created` | | |
| `Refused` | | |
