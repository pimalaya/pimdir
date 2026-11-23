# The frame every migration plan shares

Written on 2026-11-23. The seven lane plans (six consumers and io-pimdir) cite this file rather than copying it: a lane reads it first, then its own plan.

## 1. What "the new pimdir" is

- pimdir master e40b258 (pushed 2026-11-23): storage-draft-17, sync-draft-15, search-draft-17, all three untagged (the last tags are storage-draft-14, sync-draft-14, search-draft-14). Two nights produced it: a smaller pimdir (pimdir cairn/changes/a-smaller-pimdir: proposal.md, decisions.md, report.md, consumers.md) and a smaller sync (pimdir cairn/changes/a-smaller-sync: report.md, moves.md, candidates/).
- io-pimdir master 7f16b27da3b11a42b9d81a522a3e6fa5eeeed994 (pushed 2026-11-23) implements them. Its Cargo.toml still says 0.19.1, while CHANGELOG.md's Unreleased section holds every change since the 0.19.1 release, many marked BREAKING: read that whole section, it is the API and format delta every consumer crosses. io-pimdir cairn/log/2026-11-22-a-smaller-pimdir.md, 2026-11-23-the-night-perf-pass.md and 2026-11-23-a-smaller-sync.md say what moved and the measures.
- Every consumer is on io-pimdir 0.19.1 from crates.io except neverest (git pin b080e14) and himalaya (git pin dc19b8d).

## 2. How a lane moves its app

- The dependency moves by `[patch.crates-io] io-pimdir = { git = "https://github.com/pimalaya/io-pimdir", rev = "7f16b27da3b11a42b9d81a522a3e6fa5eeeed994" }`, the requirement staying `version = "0.19.1"` until io-pimdir is released (no comment inside dependency or patch sections, owner rule). The last step of every plan swaps the pin for the released version once the owner has released it (expected 0.20.0, published by io-pimdir's tag workflow, never by hand).
- Drafts are exact: a build on storage-draft-17 refuses every store an earlier draft wrote, which is moved aside and synced anew. No migration code, no reconcile, no shim, no upgrade fixture for draft stores (owner rule). What a plan owes users is a clear refusal and a documented "start over" path.
- The five CLIs share one store and one index: neverest syncs them, himalaya, cardamum, calendula and carillon read them (and some queue actions neverest drains). They must all land on the same io-pimdir revision before any of them is released, or a user's CLIs refuse each other's store. The Android app has its own private store.
- Stores and indexes refused or rebuilt: an index of search-draft-16 or earlier is rebuilt by the indexer and refused by a query client until then.

## 3. Who edits what

- An app lane edits only its own repository. It never edits io-pimdir, pimdir or another app, even to fix a bug it finds there.
- A seventh lane, io-pimdir's (io-pimdir cairn/changes/what-the-consumers-need), owns every io-pimdir and pimdir edit: the known engine defects, the vectors that pin their fixes, what the app lanes ask for, and the release preparation.
- An app lane that needs something from io-pimdir writes it to needs-io-pimdir.md in its own change folder (what, why, the evidence, the app test that shows it, whether the lane can work around it meanwhile), then works around it or parks the item. The io-pimdir lane reads those files at each of its checkpoints. No two sessions write the same file.
- Known io-pimdir defects, owned by the io-pimdir lane (pimdir cairn/changes/a-smaller-sync/report.md, candidates/k3_rekey.rs and k4_drain.rs): rekey departs from SYNC §4 and §8 in nine reproduced cases, two of them silent losses (R4, an owed flag push never pushed once a listing's flags are unknown; R1, a conflict listed with no revision cleared and its body made collectable); the queue drain mints a second item for a Copy or Move into a collection where another source holds the identity, where `store.mutate` joins it (K4). neverest runs rekey on `Renumbered`; Android does not. An app lane exposed to one notes it, and adds its app-level test once the fix is released to it.

## 4. Git

- The owner grants git writes when launching a lane. The plan's default, matching the earlier nights: commit unsigned on master after each gated step (`git -c commit.gpgsign=false commit`), conventional messages, no Co-Authored-By or any AI trailer, never push, never tag, never publish. Re-signing before a push is the owner's step (recipe: `git rebase -f -S origin/master` with the trees untouched, then one signed commit pointing every hash reference at the re-signed commits).
- Subagents of a lane stay read-only on git, always. Never use git to recover a file.
- An app lane pins only pushed io-pimdir revisions: 7f16b27 to start, then each drop of the io-pimdir lane once the owner has re-signed and pushed it (re-signing changes the hash, so an unsigned drop is never pinned).

## 5. Running seven lanes on one machine

The machine: 16 cores, 32 threads (CPU n and n+16 are one core; cores 0 to 7 one CCD, 8 to 15 the other), 121 GB of memory, /home on ext4 with about 270 GB free, /tmp a 61 GB tmpfs shared by every session.

- Builds: `CARGO_TARGET_DIR` on /home (the repository's own target/ or the lane's scratch under ~/code/pimalaya/.lanes/<lane>/), never /tmp; `-j 4`; pinned with `taskset -c` to the lane's CPUs. `CARGO_PROFILE_DEV_DEBUG=0` where debug info is not needed.
- CPU sets: neverest 0,1,16,17; himalaya 2,3,18,19; cardamum 4,5,20,21; calendula 6,7,22,23; carillon 8,9,24,25; android 10,11,12,26,27,28; io-pimdir 13,14,29,30. CPUs 15 and 31 are the measuring core, used only by the lane holding the measure lock.
- Locks, `flock` files under ~/code/pimalaya/.lanes/locks/: `measure` (one lane measures at a time, pinned to CPU 15), `servers` (one lane at a time starts the local Stalwart or Radicale containers; neverest's tests/pasta.sh shifts the ports for rootless docker), `store-517k` (taken shared by readers of the bench store, exclusively by nobody: lanes copy it before any write).
- Measures: hyperfine; binaries copied to ext4 (three copies, runs rotated), an A/A check of two builds of one tree agreeing within 1% first, old and new interleaved. A table measured while other lanes build is marked so; the final tables are re-run in a quiet window at the end of the lane.
- Fixtures: a 517k-message Enron store at storage-draft-17 with its search-draft-17 index at ~/code/pimalaya/.pimdir-night/sync-perf/store (5.2 GB, mail only, read-only: copy it before any write); the pimdir generator (io-pimdir spec/generator) builds contact, event and task stores of a chosen size. No fixture of an earlier draft survives (bench stores of the nights were deleted).
- Local servers (Stalwart, Radicale in rootless docker) only under the `servers` lock.

## 6. Accounts and secrets

- No live run without the owner's grant for that run. Never posteo (the owner's personal account): never connect to it, probe it or use it.
- Allowed when granted: Google (pimalaya.org Workspace, service account), Microsoft (test tenant), Fastmail (pull-only), iCloud (test account). Their corpus is kept: a run writes only in collections it creates and deletes only those.
- Secrets through shell variables loaded from `pass`, never printed in a reply, a tool argument, a log or a fixture. gpg's pinentry blocks `pass` from an agent shell, so a live run may need the owner present.

## 7. How a lane decides and stops

- Nothing blocks: the lane decides, writes the decision with its reason in journal.md (in its change folder, timed), and goes on. A decision that changes a user-visible behaviour beyond what the migration forces is listed for the owner with the default the lane took.
- Never weaken a test, never change production code to make a test pass, never theorise from code alone: reproduce, then fix, with a test that fails before the fix.
- A gate failing twice on one step: park the step with its evidence in journal.md and go on to the next independent step.
- A silent loss is never acceptable: a finding that could lose user data is reported first in report.md, whatever its size.

## 8. What a plan must contain

The change folder is `cairn/changes/follows-storage-draft-17/` in the app's repository (`what-the-consumers-need` in io-pimdir), with:

- proposal.md, frontmatter `cairn: change`, `id`, `status: active`, `created: 2026-11-23`: why, what, the frame above as it applies to this app, scope in and out (with the reason for each item left out), the decisions D1, D2... each with its default, the risks.
- tasks.md, frontmatter `cairn: tasks`, `change`: the steps as checkboxes, each naming the files and lines it touches, the commands to run, the gate that closes it and the evidence expected. Ordered so a session can run it top to bottom unattended.
- delta.md: what the app's cairn/spec gains, changes or loses, under the literal headings `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements` (a heading with nothing under it says "None.").
- inventory.md: the evidence the plan stands on, measured today (build errors, failing tests by name, SQL hits with file:line, open lines triaged with their source).
- needs-io-pimdir.md, when the app needs anything from io-pimdir.

The plan covers, each where it applies:

- A. Dependency and build: the pin, the features (io-pimdir split `search`, `indexer`, `mail`, `contact`, `calendar`, `client`, `vendored`), Cargo.lock, nix packaging and CI (git sources in the nix build, `nix flake check`, the pimalaya/nix workflows), cargo deny, MSRV.
- B. Compile breaks, each with its fix.
- C. Format strings and refusals: stamped draft names in code and tests, the refusal and "start over" messages, byte patches of `FORMAT_VERSION`.
- D. The app's own SQL against store or index tables that moved (storage-draft-17: flags as `items.keywords` and `bindings.base_keywords`, one `summary` table and one `summary_value` table, `queue.collection ON DELETE RESTRICT`; search-draft-17: no `chunk` or `thread` table).
- E. Behaviour inherited from io-pimdir that users see: search refusals (`reserved-form` for `~`, `/`, `{`), the five sort orders and their names, `mid:`, instants and new relative units in `date:` and `when:`, `label:` and `property:`, item properties, the `pimdir` binary's JSON contract, the faster paths, and anything else in the Unreleased CHANGELOG that reaches this app.
- F. Sync, for an app that syncs: `settled_collections`, `PimdirWriteOp::LandPlacement` and `PimdirPushResult::assigned` (COPYUID), `server_object_id` (EMAILID, X-GM-MSGID, JMAP `Email/id`), `body_flush`, the rekey and drain defects of §3.
- G. Bugs: every open line on the app's pimdir surface (store, sync, search, queue) from its cairn changes and logs ("Left" sections), the family ledgers, the CLI analysis, GitHub issues, the pimdir audits; each reproduced or with its evidence, a fix, and a regression test that fails before the fix. Lines outside that surface are listed as out of scope with the reason.
- H. Performance: the app's hot paths on its pimdir surface, a baseline at the app's head on 0.19.1 and the same measure after, the commands, the acceptance threshold, and the fixture used.
- I. Docs: the cairn spec fold, the log entry, CHANGELOG.md (Keep a Changelog, a BREAKING line where users feel it), README and man pages, the "start over" note for users.
- J. Tests: unit and integration offline, local servers (under the lock), live (owner grant), and a cross-app check (a store and index neverest writes on draft-17 read by this app; a queue row this app writes drained by neverest).
- K. Release readiness: what waits on the owner (io-pimdir release, pimdir tags, the app's own version and release), in order.
- L. The report the lane leaves at the end (report.md in the change folder), short, for the owner.

## 9. Prose

English, as the repositories' docs are. No em dashes anywhere. Markdown never hard-wrapped: one paragraph or bullet per line. Absolute dates. File paths bare or as markdown links, never in backticks; backticks for identifiers, code and commands. Shell fences ```sh.
