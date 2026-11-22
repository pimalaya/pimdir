# Decisions taken during the night

One entry per decision a doubt asked for, in the order taken: what was decided, why, and how to undo it. The owner reads this in the morning.

## 2026-11-22 21:14, the start

- **Commits carry no attribution trailer.** The harness asked for one; the owner's global instructions forbid it in commits. Undo: none needed.
- **The consumers' figures are not a gate.** No port tonight (owner), so a regression in a CLI is not measured; consumers.md lists what moved for each.
- **io-pimdir's own SQL stays under spec/.** The statements, the index schema and the generator stay at spec/queries/, spec/migrations/search/ and spec/generator/ rather than moving to a new sql/ directory: build.rs, the generator's tree lookup and twenty test files read those paths, and a rename costs churn for nothing tonight. tests/spec_drift.rs now compares only spec/migrations/storage/, spec/vectors/ and spec/payloads/ with pimdir. Undo: a rename of the three directories and their readers, mechanical.
- **Baseline clippy, fmt and no_std skipped.** They would have contended with the first move's builds; CI keeps them green, and they run at each checkpoint.
- **The other session was not told.** pimalaya-c1 is not reachable from this one (Remote Control off); a session editing pimdir or io-pimdir tonight would collide with this work.
