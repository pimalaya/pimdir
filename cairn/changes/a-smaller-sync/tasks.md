---
cairn: tasks
change: a-smaller-sync
---

# Tasks

One night, its clock counted from the owner's GO (T0, about 21:00). P is ~/code/pimalaya/pimdir, I is ~/code/pimalaya/io-pimdir, N is ~/code/pimalaya/.pimdir-night (plain directories on disk, not the tmpfs), D is N/sync-diff, K is N/candidates. Budgets are wall time; a move over one and a half times its budget is rolled back from its checkpoint and listed. journal.md here is appended at every checkpoint.

Commands: io-pimdir through its own shell, `nix develop --command cargo test --all-features` from I; pimdir through `nix flake check path:$PWD` from P; python through `nix-shell -p python3`; never perl.

"The gate" is design.md §7, items 1 to 5. "The quick gate" is the oracle on the 200 vectors and 2,000 generated scenarios plus `cargo test --all-features --test vectors_sync --test engine`, run while a move is in progress.

Three lanes: the lead's (steps 1 to 6, the only one editing I), the document's (step 7, sub-agents editing SYNC.md only, the lead reading every diff), the candidates' (step 8, sub-agents on copies under K, never the tree). While the lead measures, N/measuring exists and the other lanes start no build: they wait on that file being gone.

## 0. Before the night (owner present)

- [ ] D1 to D8 of proposal.md confirmed
- [ ] N cleaned of the bench stores the owner agreed to delete (84 GB), keeping perf/bin, perf/stores/final-x1, nm-x1 and the scripts
- [ ] journal.md opened: the commits read (P, I, neverest 99384ff, android c21fb53), the hour
- [ ] First commit in P (this change folder), so a signing prompt shows now
- [ ] Checkpoint 0: P and I copied to N/checkpoints-sync/00-baseline (no target/, no .git)

## 1. The baseline (60 min)

- [ ] I: the full suite, clippy, fmt, the no_std build; results and wall time in N/sync-baseline/
- [ ] tools/sizes.sh here: lines of code and inline tests per engine file, the public items of the seam (`cargo public-api`, or a grep of `pub` under src/ for the files of design.md §1.1), SYNC.md words per section
- [ ] The no-op and the 300-message incremental at 517k: base binary, notmuch new, one hyperfine run each on an idle core (scripts from N/perf/agents/incr and N/perf/agents/noop)
- [ ] W1's question: a fresh round over one 30k-message folder, the last page's load timed against the whole round and against the listing before it; then the same for a band round, which lists less than it loads. The two ratios go to the journal and decide whether W1 is proposed at all
- [ ] neverest, a sub-agent beside step 2: `git archive 99384ff` to N/neverest; its io-pimdir pin to I by path; the storage-draft-17 port from P/cairn/changes/a-smaller-pimdir/consumers.md and what drifted since b080e14; its suite once, every failure listed as the baseline (90 min cap, D4)

## 2. The oracle (150 min)

design.md §4.

- [ ] D/old from `git archive 131f9bf`, the first `name =` of its Cargo.toml renamed; the manifest of §4.1; I's Cargo.lock copied; the target directory under D, `TMPDIR` on the tmpfs; one release build
- [ ] side.rs, included twice: open, seed, the lockstep driver returning a trace, the masks of §4.2, the report, the row dump by natural key, the load battery
- [ ] The vector runner copied from I/tests/vectors_sync.rs (its first ten lines, `pending` and the expectations out, the spec directory hardcoded); the 200 vectors, old against old
- [ ] The server model on plain types and its two adapters; the seeded generator with weights by flag, the forced shapes, the cuts, the shrink (§4.3)
- [ ] Throughput measured on the first 1,000 scenarios; the per-gate count adjusted if under 100 a second, and written to the journal
- [ ] Old against old: 200 vectors and 20,000 scenarios, no disagreement
- [ ] Three plants in a copy of the tree at the lines of §4.4, each caught; seeds and step counts in the journal. A plant not caught is a generator gap: fixed before going on
- [ ] Old against the tree: no disagreement; checkpoint 1 (no commit: nothing in I moved yet)

## 3. T1, small duplicates (30 min)

moves.md T1.

- [ ] One `is_mutable`, one `stored_body`, `staged_edit` in rekey's `carry`, one `restaged`
- [ ] The gate; checkpoint 2; commit

## 4. T2, one policy verdict (45 min)

moves.md T2.

- [ ] `verdict` and the diverged-placement constructor; sync's `resolve_conflict` and upgrade's `settle` matching on it, each keeping its effects; `body_read` asked without a `StoreObject`
- [ ] The oracle weighted to conflicts (moves.md T2's list)
- [ ] The gate; checkpoint 3; commit

## 5. T3, the no-op's fixed cost (60 min)

moves.md T3.

- [ ] `read_hub` of no link in `load`; measured alone
- [ ] BEGIN and COMMIT of a load through cached statements, rollback on an early return; measured alone
- [ ] Statements prepared from header-less text, the public constants unchanged; measured alone
- [ ] Each kept only beyond noise; the no-op with every folder synced against the base and notmuch new
- [ ] The gate, the load battery read with care; checkpoint 4; commit

## 6. T4, the collections a run may skip (90 min)

moves.md T4.

- [ ] The read, its statement under I/spec/queries/storage/read, the six conditions; its plan on the 1M store, its time (an index only over 1 ms, added to P/migrations/storage/0001_init.sql in place, I's copy following, checks/schema.sh and checks/floor.sh green)
- [ ] The test: settled after a clean sync, not settled after each of the six ways out
- [ ] The oracle's settled check on every generated end state, the share of settled states reported
- [ ] pimbench skipping what is settled and unchanged; the no-op both ways against notmuch new; the 300-message incremental unchanged
- [ ] I: cairn/spec/sync.md ADDED, CHANGELOG.md under Unreleased
- [ ] The gate; checkpoint 5; commit

No move of the lead starts after 03:30.

## 7. The document (a lane from step 2 on, read at 04:00)

design.md §5. The lead does items 1 and 3 between its own steps.

- [ ] 1. The base frozen; tools/ledger.py; rules.tsv's old columns for every sentence; the owner map; the four table shapes; the lead-in list
- [ ] 2. Preamble, §1, §11, §12, and the self-contained paragraphs of §4 and §7
- [ ] 3. §5: absences and guards, rounds and heads, the content axis, deletes, moves and delivered creates, refusals, events
- [ ] 4. The rest of §4, §6, §9
- [ ] 5. The rest of §7, §8
- [ ] 6. §3, §2, §10
- [ ] 7. The ten sentences of §5.4, each alone
- [ ] 8. The adversarial read, one agent a family; every finding fixed or answered in the ledger
- [ ] tools/ledger.py green; at most 14,000 words; checks/references.pl on a copy of the tracked files; `nix flake check path:$PWD` (the vectors unchanged)
- [ ] OVERVIEW.md and vectors/README.md where they paraphrase a moved sentence; README unchanged (sync-draft-15 stays, untagged)
- [ ] A section not through its review by 04:00 keeps today's text: the document lands whole or section by section, never half-reviewed

## 8. The candidates (a lane from checkpoint 1 on, until 04:00)

moves.md §3. Each on a copy of the tree under K, 40 minutes, a sub-agent; the oracle in report mode where it applies. Nothing reaches I.

- [ ] K3, rekey: one test for each of R0 to R8, R3 first; each "reproduced" or "not reproduced" with the test's source kept
- [ ] K4, the drain against `store.mutate`: a Copy and a Move beside another source's item, both paths, the key each takes
- [ ] K1, one landing: upgrade's landing on sync's predicate; the classes of scenario that change, one shrunk example each, the lines saved
- [ ] K2, the status derived: the batches that differ, whether any row does, the lines saved

## 9. The end (04:30 to 06:00)

- [ ] The oracle at 100,000 scenarios, old against the final tree
- [ ] The whole gate; neverest's suite on the port
- [ ] The measures: base, final, notmuch, one table
- [ ] tools/sizes.sh again; proposal.md's table filled with what was reached
- [ ] P/checks/io-pimdir.rev names I's last commit; `nix flake check path:$PWD`
- [ ] P: cairn/log/<date>-a-smaller-sync.md; I: its own log entry, naming each move and the oracle runs that guarded it
- [ ] report.md here: the table before and after; each move with its checkpoint, or why it was rolled back or skipped; the oracle's runs and what it caught; K1 to K4 as three lists for the owner (rule changes with what each moves, behaviours reproduced, W1's two ratios); every decision of decisions.md in one line; what was not verified; the doubts
- [ ] Both trees clean but for what the report names; nothing pushed; the memory note updated

## If the night is cut short

The last line of journal.md names the last checkpoint and the step in progress. Whoever resumes restores both trees from that checkpoint's copy under N if the step in progress left them red, never through git, and goes on from the step named.
