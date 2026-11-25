#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Holds the cases a release froze to an intact prefix (README.md, Status):
# a line of checks/frozen.sha256 written `<sha256>  <path> <pointer>=<count>...`
# names a case file and lists in it, by JSON pointer, with the length each
# had at the release, and states the SHA-256 of that file's JSON with each
# such list cut to that length. The check fails when the file is gone, a list
# holds fewer entries, or the digest differs: a later version appends cases
# and edits, reorders or removes none, nor anything else the file states.
# The lines are none while every part is a draft, and the check then passes
# on nothing. checks/frozen.sh reads the lines of two fields alone.
#
# The digest is taken over the JSON written with its keys sorted by code
# point, no whitespace and no escape but those JSON requires, in UTF-8, so
# a file re-indented keeps its digest and a value changed does not.
#
# Usage: appended.py <repository root> [list]
#        appended.py <repository root> --digest <path> <pointer>...
#
# The second form prints the line to add at a release.
import hashlib
import json
import sys
from pathlib import Path


def resolve(document, pointer):
    """The list a JSON pointer names (RFC 6901), None when there is none."""
    node = document
    for token in pointer.split("/")[1:]:
        token = token.replace("~1", "/").replace("~0", "~")
        if not isinstance(node, dict) or token not in node:
            return None
        node = node[token]
    return node if isinstance(node, list) else None


def cut(document, pointer, count):
    """The document with the list `pointer` names cut to `count` entries."""
    tokens = [token.replace("~1", "/").replace("~0", "~") for token in pointer.split("/")[1:]]
    node = document
    for token in tokens[:-1]:
        node = node[token]
    node[tokens[-1]] = node[tokens[-1]][:count]


def digest(document):
    text = json.dumps(document, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")

if sys.argv[2:3] == ["--digest"]:
    path, pointers = sys.argv[3], sys.argv[4:]
    document = json.loads((root / path).read_text(encoding="utf-8"))
    counts = [f"{pointer}={len(resolve(document, pointer))}" for pointer in pointers]
    print(f"{digest(document)}  {path} {' '.join(counts)}")
    sys.exit(0)

listing = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "checks" / "frozen.sha256"
failures, frozen = [], 0
for line in listing.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if not fields or fields[0].startswith("#") or len(fields) < 3:
        continue
    frozen += 1
    want, path, lists = fields[0], fields[1], fields[2:]
    file = root / path
    if not file.is_file():
        failures.append(f"{path}: its cases frozen by a release, and gone")
        continue
    document = json.loads(file.read_text(encoding="utf-8"))
    for stated in lists:
        pointer, _, count = stated.partition("=")
        held = resolve(document, pointer)
        if not count.isdigit() or held is None:
            failures.append(f"{path}: {stated} names no list and its released length")
        elif len(held) < int(count):
            failures.append(f"{path}{pointer}: {int(count)} cases frozen by a release, {len(held)} now")
        else:
            cut(document, pointer, int(count))
    have = digest(document)
    if have != want:
        failures.append(f"{path}: its released cases and fields at {want}, now {have}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    print(f"{len(failures)} frozen case file(s) moved: a release's cases are extended by appending alone", file=sys.stderr)
    sys.exit(1)
print(f"{frozen} frozen case files hold their released cases as a prefix")
