---
cairn: log
change: five-freeze-decisions
landed: 2026-11-25
---

# Five freeze decisions

The owner's decisions of 2026-11-25 on the open line of cairn/changes/the-freeze-plan/tasks.md ("Owner decisions pending"), raised in cairn/log/2026-11-20-keep-local.md, 2026-11-20-what-an-overlay-shows.md, 2026-11-20-a-hash-key-names-its-bytes.md, 2026-11-20-the-shoulds-and-mays-reviewed.md and 2026-11-21-the-json-output-is-a-contract.md. The parts move to storage-draft-18 and sync-draft-16, both edited since their tags (bd36f0e) and owing the bump already, and to search-draft-18: SEARCH's Status line alone changes, to require storage-draft-18, and its tag search-draft-17 makes any change a bump (checks/tags.sh).

## 1. KeepLocal stays content-only (SYNC §5)

- *KeepLocal governs content alone*: a flag change and a deletion made on a store-authoritative source's remote alone merge and propagate as under any policy, the flag axis (§9) and the deletes (§5); the store pushes no flag back, and re-creates a member its remote deleted only where any policy re-stages one, its placement holding a body its base does not (vector 16). The bullet's "a change made on that remote alone is never pulled" now reads "a content change". OVERVIEW.md says so in its words.
- Checks: vector 224 (a remote-only `\Flagged` is pulled, `FlagsChanged`, nothing pushed) and 225 (a card a complete round finds absent is dropped `Deleted` and retained, no `Add`). No vector pinned either under keep-local before (174 and 175 alone ran it). Both pass on io-pimdir before and after: they pin today's reading against an engine stretching keep-local over flags or membership.

## 2. Where a copy or a move stages its create (SYNC §7, §10; STORAGE §15.2, §15.3)

- *The create is a pending create of a source syncing the target*: the run's source where it syncs the target, carrying the source's origin (vector 178, unchanged); otherwise the source an `add` into the target runs as (STORAGE §15.2, the owner's own where it is among them), with no origin of the run's source, delivered from an origin of its own (§3) or by upload, the move's tombstone then offering no destination, its `Remove` a plain delete. Written in the transaction of the move's tombstone. Vectors 227 (copy) and 228 (move): `a` syncs Contacts, `b` alone syncs Work by a checkpoint; the create is `b`'s, provisional handle, no base.
- *The target is read as the source the create is staged under*: the revive of a tombstone the source binds itself (SYNC §7, vectors 216, 217) applies to that source's own. Vector 230: `b`'s tombstone of the identity in Work, its delete unpushed, is revived under `w.vcf` when `a` copies the card there.
- *No source syncs the target: refused.* A `Copy` or a `Move` into a collection holding no binding nor checkpoint MUST be refused, staging nothing in either collection, and a queued one parks (STORAGE §15.3). Vector 229 (a move). The two readings were writing the item there unbound, as §14.3's collections no source syncs hold theirs, or refusing. Refusing, because: a copy's and a move's target half is a pending create (§5, §7), which only a source holds, and a collection no source syncs holds no binding; the store cannot tell a collection a source is about to sync from one kept on the device, both holding no binding nor checkpoint, so an unbound write decides for the person that a moved message leaves its server, the tombstone pushing a plain delete while no source pushes the item (io-pimdir projects no item no binding names, src/hub.rs `project_with`, so such an item would never reach a server once one synced the collection); and STORAGE §15.3 already parks the crossing the other way (a move or a copy out of such a collection), the explicit write being the remedy both ways. Nothing is lost: the action fails whole.
- The bodiless refusal (vector 135) stays: a placement holding no body is copied or moved only by its own based binding into a target its source syncs.
- §10 states the load and the write: the sources syncing the target name the staging source, the target is loaded as it, and the batch writes the create as it and the tombstone as the run's.
- Checks: vectors 227 to 230, each failing on io-pimdir at 769dfba (the run API and, for 227 to 229, the drain: `bindings rows differ`, the create bound to `a`; 229 `the run failing differs`); checks/vectors.py now holds every `Copy` and `Move` case to the rule (a create bound by the run's source where it syncs the target, else by a source syncing it; a failure with the rows unchanged where none does), which a copy of 227 bound to `a` and of 229 not failing both trip.

## 3. A stated `alt:` key stays unchecked (SYNC §7, STORAGE §15.3)

- *Only a `hash:` key is checked against the body*: a stated `alt:` key, read from decoded header fields rather than the bytes, is staged as stated. Vector 226 (an `Add` of a message stating no `Message-ID`, under the `alt:` key of another sender, staged under it), beside 176 and 177; checks/vectors.py requires such a case to stage under the stated key. It passes on io-pimdir before and after: the rule pins its reading.

## 4. The attachments collection's id is a MUST (STORAGE §14.3)

- *That collection's id MUST be the account, `/`, `U+0001` and `attachments`, or `U+0001` and `attachments` alone*. Vector 70 pins the bare form (its expected `collections` rows, compared whole); io-pimdir's tests/attachments.rs pins the account's (`work/\u{1}attachments`). An owner declaring another id fails both; no new check.

## 5. The binary's schema `$id` after 1.0

- No normative part moves: STORAGE, SYNC and SEARCH say nothing of the binary. The family rule, `v0.<minor>` below 1.0 and the major from 1.0, which `formatVersion` states, is io-pimdir's cairn/spec/cli.md, which pimalaya-cli's registry already follows; io-pimdir's tests/json_contract.rs `every_schema_id_names_the_contract_version` now pins it (io-pimdir cairn/log/2026-11-25-five-freeze-decisions.md).

## Versions

storage-draft-18, sync-draft-16 and search-draft-18 on the Status lines, README.md, AGENTS.md, STORAGE §4.2 and §17, SYNC §10 and §12, SEARCH §2 and §12. vectors/manifest.json restated (230 sync cases). conventions/gtd.md keeps its Status line (storage-draft-17 and search-draft-16, stale before this change; gtd-draft-05 is untagged). STORAGE §9's "(SYNC.md §6, §14)", which bd36f0e wrote and checks/references.pl refuses (SYNC numbers no §14), reads "(§14; SYNC.md §6)", so `nix flake check` passes again.

## Left

- Promoting a narrowed round's `enumerated` to MUST (SYNC §5), listed beside the attachments id in 2026-11-20-the-shoulds-and-mays-reviewed.md, was declined by the owner the same day: it stays a SHOULD, no text moving.
- checks/io-pimdir.rev still names 1f4cd35: checks/implementation.sh is red until it names the io-pimdir commit landing this.
- An implementation driving `PimdirMutate` with a storage of its own (the Android app's offline driver) loads and writes the target as the staging source and passes `target_synced` itself.

Checked: `nix flake check path:$PWD`; io-pimdir's suite over this tree's migrations, vectors and payloads.
