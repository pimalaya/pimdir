---
cairn: change
id: a-smaller-sync
status: draft
created: 2026-11-23
---

# A smaller sync

## Why

a-smaller-pimdir (the night of 2026-11-22) shrank storage and search and left the sync engine alone, as the owner ruled: "sync est compliqué par défaut et doit être manipulé avec plus d'attention". On 2026-11-23 the owner asked for the same plan for sync, then for a detailed plan of its changes. The engine holds about 12,500 lines of code across 15 files. SYNC.md holds 19,071 words, 5,330 of them in §5. Both grew one finding at a time, and most findings were silent data-loss classes.

A first reading found the weight in the code's shape: the same decision made in two to four places, a status computed and then dropped, the whole collection loaded to close a round, a document stating one rule in up to six sections. A second reading, line by line, of each place the first one named, found that most of those places do not decide alike. Sync and upgrade land a pending create under different rules. Rekey's merge agrees with sync's in 8 cases of 22. The drain and `store.mutate` key a copy differently in one case. Merging them is not a refactoring: it changes what a run does.

So this change is smaller in the engine than first proposed, and says so. design.md holds the readings and the target, moves.md every change one by one, tasks.md the night step by step.

## The principle: behaviour is frozen

Storage could redraw its tables, because every reader followed the schema. Sync cannot be redrawn that way: every rule in it is a data-loss lesson, and two consumers (neverest, and the Android app through a hand-written JSON wire and a second implementation of the write in Java) drive the engine through its public types. So what lands tonight holds the strongest sameness (L0 of moves.md): every yield of a run but its loads is the same text in the same order, and every row is the same after it.

The proof is a new **differential oracle** (design.md §4). The engine of io-pimdir 176e0b7 and the engine of the tree run side by side over the 200 vectors and over generated multi-source histories against one scripted server. It is shown able to fail on three planted bugs before it gates anything. It runs beside the 200 vectors (files unchanged, byte for byte), the engine tests (unchanged), and neverest's sync tests on a scratch port.

The same oracle, in a relaxed mode, measures what does not land: each merge that would change a rule is built on a scratch copy and reported with what it moves.

## What the morning holds

| | Before | After the night |
| --- | --- | --- |
| A differential oracle for the engine | none | built, proven on three planted bugs, kept under .pimdir-night |
| Engine code (no inline tests) | about 12,500 lines | about 12,450 |
| The source's conflict policy decided | in sync and in upgrade | by one function both call |
| No-op sync, 517k Enron, `pimbench sync`, every folder synced | 86.9 ms (notmuch new 50.2) | about 60 to 65 ms, measured |
| The same, settled folders skipped (a new store read) | | about 18 ms, measured |
| SYNC.md | 19,071 words | at most 14,000, every requirement kept (a ledger a script checks) |
| Rule changes that would shrink the engine | unknown | each built on a scratch copy, with its lines saved and the scenarios it changes |
| Rekey's own behaviours, untested (nine), and the drain against `store.mutate` (one) | read, not proven | each reproduced by a test, or refuted |
| Public items of the engine's seam | | one added (the settled-collections read), none changed |
| Sync vectors | 200, passing | the same 200 files, passing |

## What the morning does not hold

- **The engine is not 2,000 lines smaller.** The first version of this proposal said at most 10,500 lines. Those lines sit behind rule changes (one landing rule, rekey's rules, the status), each the owner's to rule on with tonight's evidence.
- **A round still loads the whole collection on its last page.** Changing it needs the wire (a count has no field, a one-page round has no answer, the Android store answers no `unstamped` to `Owing`). It is measured tonight and proposed only if the load is a real part of a round.
- **The no-op with every folder synced stays above notmuch new.** Two of the five savings first counted are not safe (what a load answers is public; another handle of the process may write between two loads). Under notmuch is the skip's.
- **SYNC.md is not at 12,000 words.** Dedup, tables and reasons reach 14,000; lower means compressing rule sentences or moving normative text out, each a decision (D5).
- **The rules do not get fewer**, and the Android app is not ported: it gains nothing tonight and loses nothing.

## What the night does not touch

- **The wire.** `PimdirYield`, `PimdirArg`, `PimdirWriteOp` and its 15 kinds, `PimdirLoaded` and its fields, `PimdirLoadSelection`, `PimdirHub::absorb`/`reconcile`, the event and report types, the builders, the `sql::*` constants the Android Java binds by name. A field nothing reads stays.
- **The rules.** No requirement of SYNC.md is dropped, added or changed in meaning, and no vector file changes.
- **The store schema**, with one exception: an index, if the settled-collections read measures over 1 ms on the 1M store, added to storage-draft-17 in place (untagged, unpushed).
- **producer.rs, rekey.rs's `carry`, the two landings**: read, measured, reported, not edited in the tree.
- **The consumers' checkouts**: neverest is ported on a scratch copy under .pimdir-night, never in its tree.

## Owner decisions

Defaults the night applies unless the owner says otherwise before GO:

- **D1, only L0 lands.** A move that would change a batch, the wire or a rule is measured on a scratch copy and listed (moves.md §3 to §5). Default: yes. The other choice is to rule tonight on one of C1 to C3 and let it land with its vector, which also means the Android store and the vectors move.
- **D2, the wire frozen**, as above. Default: yes.
- **D3, the differential oracle gates every move**, built first, proven on three planted bugs, its stores on the tmpfs and its build on disk. It lives in .pimdir-night, is not committed, and is kept. Default: yes.
- **D4, neverest as an external oracle.** A scratch copy of neverest 99384ff (`git archive`), its io-pimdir pin pointed at the tree by path, ported to storage-draft-17 (consumers.md of a-smaller-pimdir, plus what drifted since b080e14). Its suite at the night's base is the baseline. If the port is not green within 90 minutes, the night runs without it and says so. Default: yes.
- **D5, SYNC.md rewritten through a ledger**, at most 14,000 words. rules.tsv holds one line per sentence of today: kept, merged, tabled, or cut when it is a reason, an example or a note. sync-draft-15 is untagged, so the rewrite stays sync-draft-15. Of the three levers that go lower (design.md §5.1): protocol examples to OVERVIEW.md, default yes; pointers to STORAGE where it states the same rule, default yes, each checked in the ledger; §11's field lists left to the schema, default no.
- **D6, candidates measured, never landed.** K1 to K4 of moves.md, on copies under .pimdir-night/candidates, 40 minutes each, until 04:00. Default: yes.
- **D7, the no-op.** Three store edits (T3) and one new public read (T4); pimbench skips what is settled and unchanged. Reported twice against notmuch new on the same store and core: every folder synced, and settled folders skipped. Default: yes.
- **D8, same night rules as a-smaller-pimdir**: commits unsigned (`git -c commit.gpgsign=false`), no push, no tag, no attribution trailer, nothing blocks, every doubt decided on the conservative side and written to decisions.md.

## Rules of the night

- No real account, no network, no push, no tag, no publication, no version bump.
- Writes only in pimdir, io-pimdir, ~/code/pimalaya/.pimdir-night/ and the session's scratchpad. No consumer checkout is touched.
- Sub-agents never run a git write, print no secret, and delete nothing they did not create; the lead alone commits.
- A test changes only when a type it names changed, which the wire freeze rules out: an engine test changing is a stop.
- One measuring run at a time, on an idle core, no build running.
- A move not green within one and a half times its budget is rolled back from its checkpoint (a plain copy under .pimdir-night, never through git) and listed.
- journal.md here is appended at every checkpoint. A session cut short or summarised resumes from it.
- No background waiter matches a pattern its own command line holds (3 h 40 lost on 2026-11-23): wait on a PID or a file.

## After

The log entries of both repositories, io-pimdir's cairn/spec/sync*.md folded for T2 and T4, report.md here. The owner reads its three lists: the rule changes with what each moves (C1 to C7), the rekey and drain behaviours reproduced (K3, K4), and whether a round's close is worth a wire change (W1). The Android store served by io-pimdir (design.md §8) is the change that makes the next ones cheap.
