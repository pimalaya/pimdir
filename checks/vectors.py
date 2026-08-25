#!/usr/bin/env python3
"""Re-derives every value under vectors/ from the bodies it names.

The names are checked against the algorithms of SPEC.md section 5, never
against a store: hashlib, blake3 and base64 are the second, independent path
vectors/README.md asks for.
"""

import base64
import hashlib
import json
import sys
from pathlib import Path

from blake3 import blake3

ALGORITHMS = {
    "blake3": lambda body: blake3(body).digest(),
    "sha256-128": lambda body: hashlib.sha256(body).digest()[:16],
}

failures = []


def check(label, got, want):
    if got != want:
        failures.append(f"{label}: {got} is not {want}")


def name(digest):
    """The object name: RFC 4648 section 6 base32, lowercased, unpadded."""
    return base64.b32encode(digest).decode().lower().rstrip("=")


def body(case):
    """A case's bytes, spelled out in hex or generated from its pattern."""
    if "body_hex" in case:
        return bytes.fromhex(case["body_hex"])
    return bytes(i % 251 for i in range(case["body_len"]))


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "vectors"
objects = json.loads((root / "objects.json").read_text())
meta = json.loads((root / "meta.json").read_text())

for case in objects["base32"]["cases"]:
    encoded = name(bytes.fromhex(case["input_hex"]))
    check(f"base32 of {case['input_utf8']!r}", encoded, case["base32"])

for case in objects["objects"]:
    bytes_ = body(case)
    check(f"{case['label']} length", len(bytes_), case["body_len"])

    for algorithm, digest_of in ALGORITHMS.items():
        digest = digest_of(bytes_)
        shard = name(digest)
        check(f"{case['label']} {algorithm} digest", digest.hex(), case[algorithm]["digest_hex"])
        check(f"{case['label']} {algorithm} name", shard, case[algorithm]["name"])
        check(
            f"{case['label']} {algorithm} path",
            f"objects/{shard[:2]}/{shard[2:4]}/{shard}",
            case[algorithm]["path"],
        )

for case in meta["cases"]:
    bytes_ = (root / case["fixture"]).read_bytes()

    # Named before the lengths and the digests it would otherwise break, since
    # a checkout that converted the line endings breaks all three at once.
    if bytes_.count(b"\n") != bytes_.count(b"\r\n"):
        failures.append(f"{case['fixture']}: not CRLF throughout, so something converted it")
        continue

    check(f"{case['fixture']} length", len(bytes_), case["body"]["len"])
    check(f"{case['fixture']} meta.size", case["meta"]["size"], case["body"]["len"])

    for algorithm, digest_of in ALGORITHMS.items():
        check(f"{case['fixture']} {algorithm}", name(digest_of(bytes_)), case["body"][algorithm])

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print(
    f"{len(objects['base32']['cases'])} base32 cases, "
    f"{len(objects['objects'])} object names and "
    f"{len(meta['cases'])} fixtures re-derive"
)
