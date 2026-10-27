---
cairn: change
id: pim-corpus
status: draft
created: 2026-10-18
---

# A deterministic PIM corpus generator

## Why

Opened as an idea on 2026-09-06, nothing built. Testing a sync engine or a client against live accounts does not scale: a large corpus is slow to seed and to reset, quota limited, and not deterministic, since servers rewrite headers and some dedup by `Message-ID`. Every repository meanwhile invents its own throwaway fixtures. The consumers are neverest, io-pimdir, himalaya and its TUI, the Android apps, cardamum, calendula, carillon and m2m.

## What

A corpus is a program, not a dataset: `(generator version, seed, profile) -> bytes`. The generator and a manifest digest are versioned, never the data, so a failing fixture is about 40 bytes that replay byte for byte on another machine.

Two axes kept apart:

- **Volume**, local only, two profiles: `count` (100k to 200k small items, hundreds of collections, depth 5 or more) for the store, listing and merge paths; `bytes` (a few hundred items, large attachments, one past 25 MB, one past 100 MB) for the blob store and the fetch and append paths.
- **Quirks**, a small profile (about 500 items, about 30 collections with hostile names) run against local IMAP, CardDAV and CalDAV server containers, and only then against a few dedicated test accounts.

Two layers from one generator:

- **Structure**, enumerated by hand and never sampled: a missing `Message-ID`, a duplicate one in one collection, a never-written mailbox (`HIGHESTMODSEQ` 0), modified UTF-7 names, a hierarchy separator inside a name, names differing only by case, a name that is a prefix of another, an empty collection, 100k UIDs with holes, a `UIDVALIDITY` bump, system flags and custom keywords, 8-bit unencoded headers, absurd folding, a broken or missing `Date`, CRLF beside bare LF, thread graphs with broken `References`.
- **Surface**, sampled: plausible names, subjects and bodies, so screenshots and recordings do not read `test-0042`.

Constraints already agreed:

- The PRNG is pinned by algorithm (`rand_chacha` at a fixed version, or a small owned PCG): `rand`'s `StdRng` is reproducible within a major version only, and a bump would rot every manifest.
- A manifest (item id and normalised digest) ships beside the data and is the oracle's input, so the comparator lives with the generator.
- The comparator tolerates what servers legitimately do: added `Received` headers, a rewritten `Date`, labels mapped onto folders, a `Message-ID` dedup.
- The seeder is independent of the system under test (a plain APPEND or PUT script, or an established sync tool as reference), so fixture damage is never mistaken for sync damage.
- Contacts and calendars are not regenerated: ical-rs's frozen dateutil and libical corpus and vcard-rs's corpora are vendored as fixed vectors.
- Every generated item carries a run-scoped header, so a remote cleanup is one search.

## Where pimdir comes in

The corpus is a separate repository; this change records it here because pimdir's vectors/ are the store's fixtures and the `count` profile is the store's load. A store built from a seed is how io-pimdir's and the Android store's performance numbers become reproducible (the 2026-10-11 performance audit seeded its own).

## Open questions

- Name: `io-pim-corpus` with an off-by-default `cli` feature (the core emits items and the caller writes them), or `pim-corpus` if `io-` stays reserved for substrate rather than dev tooling.
- Output adapters for a first version: m2dir on disk is certain, Maildir through m2m, then IMAP, CardDAV and CalDAV push scripts. A pimdir store directly?
- Whether the comparator ships with the generator or in neverest.
- Whether CI sweeps seeds at the small profile, a failure shrinking to a seed.

## First step

The comparator on 500 items, before generating anything large: without an oracle a big run only proves the process did not crash.
