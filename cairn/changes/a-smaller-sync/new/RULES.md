# Rules for the SYNC.md rewriters

C is /home/soywod/code/pimalaya/pimdir/cairn/changes/a-smaller-sync. The base text is C/sync-base.md (SYNC.md at e75e397), split into C/new/NN.md, one file per section (00 is the preamble and Contents). `cat C/new/[0-9]*.md` is the new SYNC.md. The method is design.md §5; read it, then C/owners.md (who owns each rule family, and the nuance each restatement carries), C/leadins.txt, and the docstring of C/tools/ledger.py.

## What you may change

- Only the section files you are assigned, and your ledger file C/new/rules-NN.tsv: the rows of C/rules.tsv whose `old_section` is one of your sections, copied with `state` and the `new_*`, `stub`, `nuance` columns filled. Never edit C/rules.tsv, C/sync-base.md, SYNC.md, or another lane's files.
- A clause that must move into a section you are not assigned: write it, with its old_id and the owner sentence it joins, to C/new/to-MM-from-NN.md (MM the owner section). The lane owning MM applies it.

## What must hold

- No requirement dropped, added, weakened or changed in meaning. Every unmarked statement binds as MUST. A key word keeps its level (MUST stays MUST, SHOULD stays SHOULD, MAY stays MAY); binds stays binding.
- A rule is stated once, in its owner's section (owners.md). A section that held it keeps a one-line pointer naming the rule and `§<owner>`, because vector files cite the old section. The clause only a restatement carried (owners.md `nuance:`) moves into the owner's sentence, word for word where possible.
- Section numbers, headings and topics stay. Every lead-in of leadins.txt stays; those marked `!` stay verbatim.
- Cut only what is a reason, an example or a note (class reason, example, note), and only where the rule reads as well without it. When unsure, keep it.
- Tables: use the shapes of owners.md. A cell states exactly what the sentence it replaces stated.
- No em dash (U+2014). No hard wrap: one paragraph or one list item per line. Backticks for identifiers. References as `§N` (a bare `§5` right after a `STORAGE §10,` is read as STORAGE's: write `SYNC §5` there, or reorder).
- Budget per section: design.md §5.1. It is a ceiling, not a target to reach by compressing rule sentences.

## How to check

Assemble into a scratch file and run the checker, then read only the failures that concern your rows and your sections:

```sh
cd C && cat new/[0-9]*.md > /tmp/claude-1000/ledger-NN/NEW.md
nix-shell -p python3 --run "python3 tools/ledger.py check sync-base.md /tmp/claude-1000/ledger-NN/NEW.md <your merged ledger> --budget"
```

where the merged ledger is C/rules.tsv with your rows replaced by those of your rules-NN.tsv (rows of other sections are still unfilled and fail; ignore those). Your lane is done when no failure concerns your rows or your sections, and `perl` is never used.

## Report

Words per section before and after, rows by state, every nuance you moved and where, every `to-MM-from-NN.md` you wrote, and anything you could not compress without changing meaning.
