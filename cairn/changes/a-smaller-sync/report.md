# A smaller sync: the night's report

Run on 2026-11-23 from 11:24 (GO) to about 14:00, unattended, on pimdir e75e397 and io-pimdir 131f9bf, under D1 to D8 of proposal.md at their defaults. journal.md holds every step with its time; this file is what the owner reads.

## In short

- **The engine did not get smaller, and the reason is now known.** Its duplicates do not decide alike: the two landings, rekey's merge, the status and the drain each differ from the path they look like in ways the tests below pin. Merging them changes outcomes, so under "behaviour frozen" the engine moved by small shared helpers and one policy verdict.
- **The sync got faster.** No-op at 517k from 89.2 to 67.6 ms with every folder synced (notmuch new 47.4), and 18.6 ms when the folders the store calls settled are skipped. A full round over 12k bindings 17 to 25% faster, a 300-message incremental 9%.
- **A differential oracle exists** (.pimdir-night/sync-diff): the old engine against the tree, in lockstep, over the vectors and generated multi-source histories, shown able to fail on three planted bugs. Every change of the night went through it.
- **Rekey breaks SYNC §8 in nine reproduced cases**, two of them silent losses. Not fixed (D1): each has its test in candidates/.
- **SYNC.md is unchanged.** A full rewrite through the ledger reached 18,019 words from 19,036 (-5%), not 12,000 or 14,000: the length is in the rules, not their repetition. It sits in SYNC-rewrite.md for the owner to judge.

## Before and after

| | 131f9bf | io-pimdir d9b79e6 and the log |
| --- | --- | --- |
| No-op sync, 517k, every folder synced | 89.2 ms | 67.6 ms (notmuch new 47.4) |
| The same, settled folders skipped | | 18.6 ms |
| 300 new messages in one folder (median) | 234 ms | 212 ms |
| Full unchanged round, 11,896 bindings (in-process probe) | 408 ms | 308 to 341 ms |
| Its last-page whole-collection load | 144 ms | 91 ms |
| Engine code (tools/sizes.sh, 15 files) | 12,364 lines | 12,655 lines |
| Public items | | one added, `PimdirSourceStore::settled_collections`; none changed or removed |
| Places deciding a source's conflict policy | 2 | 1 verdict, two sets of effects |
| Tests | 1,171 passed | 1,180 passed (T4's 9) |
| neverest 99384ff on a scratch port | 727 passed | 727 passed |
| Sync vectors | 200 | the same 200 files, unchanged |
| SYNC.md | 19,036 words | unchanged (a rewrite at 18,019 beside it) |

Engine code grew by 291 lines: T6's streaming loads (about 240) and T4's read; the engine's own files shrank by about 40.

## The changes, each gated

The gate (design.md §7): the oracle on the 200 vectors and 20,000 scenarios, the whole suite, clippy, fmt, the no_std build, the vectors and engine tests unchanged, neverest's suite. Results in .pimdir-night/gates/<label>.txt.

| Move | Commit | Gate | What |
| --- | --- | --- | --- |
| T1 | b4bcf37 | pass | small helpers shared (`is_mutable`, `stored`, `staged_edit` in rekey, `restaged`) |
| T2 | 0b862e2 | pass, and 20,000 more weighted to conflicts and upgrades | `PimdirConflictPolicy::verdict` for sync and upgrade |
| T3 | 2f12b60 | pass | a load naming no link reads no hub (95 to 75 ms); cached BEGIN/COMMIT and a header-less cache key measured and dropped within noise |
| T4 | 86f0421 | pass, and the settled check over 16,814 end states | `settled_collections`, its statement, 9 tests, pimbench's `PIMBENCH_SKIP=1`, spec sync.md ADDED, CHANGELOG |
| T6 | d9b79e6 | pass (fmt fixed after: one rustfmt wrap) | whole-collection reads streamed, the projection moving out of the hub: 166 to 93 ms a load |

The final tree against 131f9bf: 200 vectors and 100,000 scenarios (1,284,825 steps), 0 differences.

## The oracle

- Old against old: 20,000 scenarios (254,614 steps), 0 differences; relaxed mode 3,000, 0. No nondeterminism in the engine.
- Plants: a flag-merge flip caught at scenario 5 (the vectors catch it too); the mass-absence threshold moved to 19 caught at scenario 16 (a forced shape; the vectors do not); the minted create landed first caught at scenario 9 (the vectors do not).
- 165 scenarios a second on 16 workers, once SQLite's memory statistics are off (with them, one global mutex held it at 7.6: worth knowing for any multi-threaded measure).
- Blind spots, measured: upgrade's landing (K1 found it never reached), an `Add` carrying `supersedes`, an `Abandoned` event, relocations and capped or narrowed rounds rarely; mail only (other kinds come through the vectors); the Android Java store never runs. Sameness is proven, not correctness.

## What the night found, for the owner

### Rekey against SYNC §4 and §8 (K3, candidates/k3_rekey.rs, 19 tests passing on 131f9bf)

| | Case | Today | SYNC |
| --- | --- | --- | --- |
| R4 | an owed flag push, the listing's flags unknown | the base takes Unknown, the row reads Clean, the flag is never pushed | §8 "A flag change still owed is pushed by the next sync": **silent loss** |
| R1 | a conflict listed with no revision | the divergence cleared, its body collectable, the next sync pushes an Update | §8 "carried as it is": **silent loss** (an if_match guards the server) |
| R3 | a staged edit under a tombstone, the server edited | revived Clean; the edit survives only as a retained item the rekey report never names | §8 and §5: a Conflict at the fetched revision |
| R2b, R2c | a conflicted tombstone | the divergence lost, or settled Clean | §8 "carried as it is", §5 no Remove |
| R0 | a listing repeating a handle | first item's flags, last item's link id and summary | §4 keeps the first |
| R5 | a delivered create matched | carried, dropped `Rekeyed`, no event | §8 "as a page lands it" |
| R6b | an offered copy whose hint a member states | minted apart, a second item | §8 "named as a page names one" |
| R7 | a base-less conflict | given a base, or re-staged | §8 "carried as it is" |
| R8 | listed bodies | ignored, Meta | §8 for a new member: as a page names it |

R2a and R6a are as SYNC states. neverest runs rekey on `Renumbered`; Android does not.

### The drain against `store.mutate` (K4, candidates/k4_drain.rs)

A `Copy` or `Move` into a collection where another source holds the identity: the drain mints a second item (`dup:` key), `store.mutate` joins the existing one. SYNC §10 and STORAGE side with `store.mutate` (a link-id load offers no create for an item the source lacks).

### The candidates that would shrink the engine (K1, K2)

- **K1, one landing for a page and a fetch:** +15 lines, not fewer; five upgrade tests change, because a fetch would then refuse another message under the hint. Rule change C1 of moves.md.
- **K2, the status derived:** 4 lines saved; not an internal change at all, since the projection's status reads the hub's kind and the item's conflict. One difference class to read: a mail body `Edit`, then a server edit carrying a revision, then a `Manual` sync: the engine today takes the server's body; the candidate records a conflict. Whether a mail member with a revision comes from a real connector is unverified.

### W1, a round closed without the whole collection

Measured: the last-page load is 35% of an in-process round before T6, 27 to 30% after. Worth proposing, but it needs a wire change (a count has no field, a one-page round has no answer, the Android store answers no `unstamped` to `Owing`): moves.md W1.

### SYNC.md

- The ledger (rules.tsv, tools/ledger.py, owners.md) splits the text into 692 units and checks a rewrite against it: nothing dropped, key words at their level, every new binding sentence traced. Its self-test catches deletion, a lowered key word and an added MUST.
- The rewrite (SYNC-rewrite.md, rules-merged.tsv) passes it, at 18,019 words. The base it is checked against is SYNC.md at e75e397 (`git show e75e397:SYNC.md > sync-base.md`, then `tools/ledger.py check sync-base.md SYNC-rewrite.md rules-merged.tsv`). Three adversarial reviews (review/A.md, B.md, C.md) still found 0 lost requirements but 2 weakened, 3 changed and 2 added, every one in a table cell or a cut "reason": the checker is blind to a condition dropped from a cell. All were fixed; the fixed text was not reviewed again.
- Per section the gain is in the restating sections (§7 -26%, §8 -21%, §6 -16%, §4 -9%); §5, §9 and §10 grew (tables, and §9 took §6's clauses). Protocol examples cut from §4 are kept word for word in the ledger's nuance column, for OVERVIEW.md.
- Fourteen wordings in today's SYNC.md read as inconsistent; each is carried unchanged into the rewrite: the three of design.md §5.4, and the eight of the ledger's report, among them `last` marked only once every member is listed while a cap leaves some out, §2's delivered-create definition narrower than §4's paths, §5 saying a mutation reports no event while §6's landings report some, and the round's head "first" binding as MUST in §5 but SHOULD later. Also: §2's Destination says "a pending create", §3 "or a delivered one".

## Decisions taken alone (decisions written in journal.md)

- The plan was written with one model and run with another (Opus 5.5), from the same files.
- An inline test's import line may follow a moved item (T1); T6 adds an equality assertion inside hub.rs's test helper. No assertion was changed or weakened.
- T3's cached BEGIN/COMMIT and header-less cache key dropped: within noise.
- T4's statement lives under owner/, rewritten from a per-collection probe (3.6 ms at 1M) to one NOT IN (2.1 ms); no index added.
- SYNC.md not replaced: -5% does not repay a diff of the whole normative text without the owner reading it, and the reviews showed tables are where meaning slips.
- K3 and K4 behaviours not fixed: each is a rule change (D1).
- Bench stores deleted as agreed: new-x1, new-x2, old-x1, nm-x2 and perf/target (54 GB).

## Not verified

- The rewrite after its fix pass (no second review).
- neverest's 52 server-backed tests (Stalwart, Radicale) and 20 live tests: never run.
- The Android app: not built, not run; it pins storage-draft-15 and would need last night's port first. Its Java store answers loads itself: T3 and T6 change no answer, so nothing it serves is touched, but nothing proved it.
- Whether R1 to R8 occur in the field (neverest's remote carries bodies; its renumbering path runs rekey).
- `checks/references.pl` on the rewrite (the rewriters could not run perl; `nix flake check` was run on the tree, where SYNC.md is unchanged).

## Next

1. Rule on R4 and R1 (silent losses in rekey), with a vector each that fails today; then the rest of K3, K4 and C1 to C7 of moves.md.
2. Decide on SYNC-rewrite.md: land it after a second review, take only its §7 and §8 (the clearest gains), or drop it.
3. The Android store served by io-pimdir (design.md §8), which would make W1, W2 and the status internal changes.
4. neverest and pimbench adopting `settled_collections`.
