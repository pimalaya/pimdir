---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The gate carries the generator

checks/implementation.sh copies generator/, without its target/, into io-pimdir's spec/generator beside migrations/, queries/, vectors/ and payloads/, so io-pimdir takes the generator as a path dev-dependency for the differential tests of the freeze plan (section 3) and runs over this tree's generator, never a copy of another revision. AGENTS.md §4 says so.

Guard: io-pimdir's tests/spec_drift.rs compares its spec/generator with the pimdir revision its spec/REVISION names, byte for byte (io-pimdir cairn/log/2026-11-20-the-spec-carries-the-generator.md); the copy checks/implementation.sh makes was compared with io-pimdir's vendored one, identical.

No part changes: the generator is tooling, binding no implementation.
