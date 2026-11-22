# Journal of the night

Appended at every checkpoint. The last entry names the step in progress; a session resuming starts there (tasks.md, "If the night is cut short").

## 2026-11-22 21:14, step 0

Commits read: pimdir b5b9382, io-pimdir 00727ba, himalaya a2726f56, neverest 99384ff, cardamum 22c0bd5, calendula 794550c, android c21fb53. Owner gave GO at 21:14 with the rulings at the top of proposal.md's decisions. Checkpoints under ~/code/pimalaya/.pimdir-night/checkpoints/.

## 2026-11-22 21:50, step 1 done, steps 2 and 3 running

Baseline: io-pimdir `cargo test --all-features --no-fail-fast` 1,089 passed, 0 failed, 8 ignored, 195 s wall; pimdir `nix flake check` passes (64 s) on a clean snapshot of 4fe9698 (a stale untracked .claude/worktrees/ in the pimdir checkout breaks the references check under `path:`, so checks run on tracked files). Sizes in .pimdir-night/baseline/sizes.txt. Clippy, fmt and no_std not run at baseline (CI keeps them green; they run at checkpoints). Checkpoint 00-baseline taken. The other session (pimalaya-c1) is not reachable: not told.

Lanes: step 2 pimdir side (agent: statements, index schema, generator and their checks leave pimdir); invariants.sh mapped to io-pimdir tests (agent, read-only, on the checkpoint copy); step 3 flags as columns (agent, io-pimdir and pimdir's schema). Lead: io-pimdir side of step 2 (spec_drift compares migrations/storage, vectors, payloads only; build.rs and the generator README restate ownership).
