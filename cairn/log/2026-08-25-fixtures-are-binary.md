---
cairn: log
change: fixtures-are-binary
date: 2026-08-25
---

# The fixtures are CRLF in the repository, not only in the tree that wrote them

vectors/fixtures/ is now marked `-text` in .gitattributes, and the blobs are re-added so they carry the CRLFs they always claimed to.

## The vectors did not describe what a clone held

Every fixture was committed through a `core.autocrlf = input` clean filter, which strips the CR on the way into the object database. The working tree that authored them kept its CRLFs, so every digest in meta.json was derived, checked and recorded against bytes that only ever existed on one machine. The blob a clone receives is one byte per line shorter: mail-basic.eml is 289 bytes in git and 299 in the tree.

That is the failure mode the vectors exist to catch, reached by the one path they could not check: vectors/README.md tells a consumer to read the fixtures as bytes, and the repository handing them out was not storing them as bytes. Nothing reported it, because nothing re-derived the values after the commit that normalised them. The first CI run that did, failed on all seventeen.

An implementation reading this repository as a sibling checkout, as io-pimdir does, was reading the converted files and would have disagreed with meta.json on every mail and calendar case.

## Two changes, both needed

`-text` alone fixes nothing already committed: it stops the conversion from here on, and the blobs still hold what the old filter left. The fixtures are therefore re-added under the new attribute, which stores the working tree's bytes verbatim. `-text` rather than `binary`, so a diff of a fixture stays readable.

## The check names the cause now

checks/vectors.py asserted lengths and digests, so a converted checkout failed three times per fixture and named the symptom each time. It now tests CRLF first and skips the rest of that fixture's checks, one line per file saying what actually happened. The class of bug is common enough (a vendored copy, a zip export, a Windows checkout) that the message is worth more than the three it replaces.
