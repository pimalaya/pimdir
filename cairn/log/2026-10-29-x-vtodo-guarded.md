---
cairn: log
change: gtd-hardening
date: 2026-10-29
---

# The x-vtodo declaration gets the scenario it was said to have

Correction to 2026-10-29-gtd-hardening.md, which named STORAGE §15.6's `x-vtodo` as guarded by checks/invariants.sh while no scenario there read it (the producer's gate was guarded by io-pimdir alone). checks/invariants.sh now holds one: a calendar a source registered with no checkpoint, as a source does for each calendar it lists, answers its `x-vtodo` row from `load_capabilities` before any item sync binds anything there; a calendar with no row states nothing by it; a calendar stating `full` wins over a source-wide `none`. No rule or statement changes. `nix flake check path:.` passes.
