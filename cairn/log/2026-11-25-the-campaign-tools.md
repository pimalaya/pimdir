---
cairn: log
change: the-freeze-plan
landed: 2026-11-25
---

# The campaign tools

Closes three lines of cairn/changes/the-freeze-plan/tasks.md: "Shrinking: a failing seed reduced and written as a vector" and "Profile: quirks" (section 2), and "The campaign's seeds and profiles fixed and recorded" (section 7). The tools live in io-pimdir (its cairn/log/2026-11-25-the-campaign-tools.md, spec/generator/README.md "Campaigns"); the campaigns are not run yet. No rule, vector or schema of this repository moved.

## What a campaign is

io-pimdir tests/generated/campaigns.json records campaign-1 and campaign-2, at generator revision 1, over distinct seeds, each running every profile: structure (64 seeds: reader, overlay, drain, index, search, owner-write and refresh crash cuts), histories (48: the twelve histories replayed and cut after every commit), quirks (160), count (16 at 5,000 items) and bytes (4 at full size). About 100,000 core-seconds each, an hour on 32 cores. A failure is written with its seed, profile, suite, history and step, and summed by suite and by signature, so D5's stop rule (two campaigns in a row with no spec break) reads off two summaries sorted by door.

## Shrinking

A replay failure is cut to one engine step, the store before it, and made smaller (queue and bookkeeping rows, collections, sources, items, mail text) while the same failure stands and no other appears, then written as a vectors/sync case at format 11, the next free number, with a label and a note to restate from SYNC before it lands, and its bodies as fixtures `generated-<object name>`. Proved on a flag merge planted in a scratch copy of io-pimdir: the shrunk case passed checks/vectors.py in a scratch copy of this tree (233 sync cases), failed the planted engine and passed the real one; it is not landed, vector 26 pinning the same rule. A failure of another suite becomes an io-pimdir test; a crash cut, spanning two runs, is reported with its history, format 11 holding one run.

## The quirks profile, first run

campaign-1's quirks seeds 1201 to 1208 (128 jobs, 295 s on 32 cores) found, by door: no spec break; spec minor, reading two ways, a DAV listing carrying another body at the base's own revision (SYNC §5 decides a pull by the revision alone), and a bodiless message's summary restated by a later listing's meta; an implementation finding in io-pimdir writing a rewritten `Message-ID` over the summary of a body it holds (STORAGE Annex A), and one in a parked round of several pages whose `round_checkpoint` differs cut and uncut; a renumbering handing every member its old handle bumping the generation in the model and not in io-pimdir (SYNC §8 bumps it with a `Rekeyed` drop). io-pimdir's log entry lists each with its evidence; none is fixed.
