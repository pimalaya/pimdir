---
cairn: change
id: cross-implementation-vectors
status: active
created: 2026-08-24
---

# Normative test vectors, so two implementations can be checked rather than compared by eye

## Why

This format has two implementations: io-pimdir over rusqlite, and the Pimalaya Android app over its own SQLite driver in Java. §4.4 anticipates a third, since it invites an implementation to run the canonical statements on whatever driver it holds. Nothing checks that any two of them compute the same values.

The schema is already checked, and that is what shows the gap: io-pimdir's spec-fidelity suite compares its inlined DDL against migrations/0001_init.sql through SQLite's own pragmas, so a missing column or a wrong foreign-key action fails a test. Every *value* the format fixes is checked by nobody. On 2026-08-24 an audit found that io-pimdir stamped `store_meta.hash_algo` with `blake3` while every Rust consumer named objects with a 128-bit FNV-1a rendered as hex, and the Android app named the same body `sha256-128` in base32. Same store, same body, two names.

The failure mode is what makes this worth a file rather than a convention: none of it errors. A store whose objects are named two ways does not report a mismatch, it silently never deduplicates and never finds a blob the other side wrote. The same is true of a summary field spelled differently and of a sort key derived differently: the list is merely emptier or in the wrong order, and no process is in a position to notice.

## What

A `vectors/` directory in this repository, holding the values every implementation must agree on, as data rather than as prose:

- **objects.json**: body bytes to object name, per `hash_algo`, plus the sharded path §5 derives from it. Authored from the algorithm specifications rather than from either implementation (SHA-256 and RFC 4648 are checkable by hand), so neither is the reference.
- **meta.json**: one fixture per kind to its expected `meta` object, `sort_key` and `link_id`. Covers the cases the prose has to hedge: a card with no `FN`, a message with an unparseable `Date`, a zoned `DTSTART` on a DST fold and on a gap, a `VTODO` with `DUE` and no `DTSTART`.
- **fixtures/**: the .eml, .vcf and .ics bodies those cases point at.

Consumers compare **parsed** structures, never JSON text: JSONObject and serde_json do not agree on key order, and fixing an order in the vectors would pin an accident rather than a rule.

SPEC.md gains a short normative section naming vectors/ as part of the format and requiring an implementation to pass it.

## What this costs each implementation

io-pimdir gets a `tests/vectors.rs` beside its spec-fidelity suite, under the same skip-when-the-spec-is-not-checked-out-beside-it guard, so it is free for anyone building from crates.io.

The Android app is the awkward one: it is not checked out beside this repository, so it cannot read vectors/ directly. Vendoring the files into its test resources with their SHA-256 recorded, plus a CI step that re-hashes them against this repository and fails on drift, keeps its tests hermetic and offline while still breaking loudly when the format moves.

## Not folded into a delta

cairn/spec/ is empty here by the deliberate deviation adopt-cairn recorded: SPEC.md is the spec. The section this change adds is described above and lands in SPEC.md directly.
