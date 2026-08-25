---
cairn: log
change: ci-without-an-implementation
date: 2026-08-25
---

# The format's CI stops depending on an implementation of it

This repository's only workflow checked out io-pimdir and io-replica and ran three of io-pimdir's Rust test suites. It is replaced by two scripts under checks/, a flake that gives them a toolchain, and a workflow whose whole body is `nix flake check`.

## Why it was the wrong direction

A format that names one implementation in its CI has inverted its own dependency. Every consumer is meant to be equal in front of SPEC.md, and a workflow that pulls one of them, in one language, along with that one's own path dependency, says otherwise. It also cost this repository a Rust toolchain to check files a shell and a hundred lines of Python can check.

It was redundant besides. io-pimdir's workflow already checks out pimdir beside itself, runs the whole suite rather than three of them, and fails when the spec suites skip. Everything the deleted job did was already happening there, on the correct side: the implementation conforms to the format, not the other way round.

## What replaces it

- **checks/schema.sh** applies every migration in order to an empty database, then compiles all 60 named statements under queries/ with `EXPLAIN`. It asserts `PRAGMA user_version` ends at 1, that `integrity_check` passes, and that `pragma_table_list` reports no table declared without `STRICT` (§4.1). A column renamed in the migration and not in the statements now fails on the push that does it, naming the file and the statement.
- **checks/vectors.py** re-derives every value under vectors/ from the bodies it names: the RFC 4648 §10 cases, then both digests, both names and both shard paths of every object case, then every fixture's byte length, its two names, and the `size` its `meta` records. It reports every mismatch rather than the first.

The flake pins nixpkgs, wires sqlite3 into the first and a Python carrying `blake3` into the second, and exposes both as `checks`, so `nix flake check` runs them and `nix develop` gives a contributor the same two tools to run the scripts by hand. They take the repository root as their argument and default to the working directory, so neither needs the flake to be useful.

## The blake3 half is now checked too

An earlier draft of this job ran on the runner's own coreutils, which have no BLAKE3, so half of objects.json went unchecked and the workflow had to say so. Pinning the toolchain removes the excuse: `blake3` is one line of a Python package set, and both algorithms are now derived and compared on every case. The vectors' second, independent path (vectors/README.md) is what CI re-runs, rather than something asserted once at authoring time.

## Not landed here

io-pimdir keeps its own spec suites and its own checkout of this repository. Nothing there changes.
