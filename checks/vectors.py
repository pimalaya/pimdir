#!/usr/bin/env python3
"""Re-derives every value under vectors/ from the bodies it names, and checks
the shape of the sync and search cases nothing but an implementation can run.

The names are checked against the algorithms of STORAGE.md section 5, never
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

TABLES = {
    "mail_summary": {"message_id", "in_reply_to", "subject", "sender", "sender_name", "date", "size", "attachment"},
    "contact_summary": {"uid", "fn", "kind", "org"},
    "event_summary": {"uid", "summary", "location", "dtstart", "dtstart_tzid", "dtstart_value", "dtend", "recurring", "until"},
    "task_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value", "due", "due_tzid", "due_value", "status", "completed", "percent", "recurring", "until"},
    "journal_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value"},
}

ROLES = {"from", "to", "cc", "bcc", "email", "organizer", "attendee"}

failures = []


def check(label, got, want):
    if got != want:
        failures.append(f"{label}: {got} is not {want}")


def require(label, condition):
    if not condition:
        failures.append(label)


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
summaries = json.loads((root / "summaries.json").read_text())

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

fixtures = set()

for case in summaries["cases"]:
    fixtures.add(case["fixture"])
    bytes_ = (root / case["fixture"]).read_bytes()

    if bytes_.count(b"\n") != bytes_.count(b"\r\n"):
        failures.append(f"{case['fixture']}: not CRLF throughout, so something converted it")
        continue

    check(f"{case['fixture']} length", len(bytes_), case["body"]["len"])

    for algorithm, digest_of in ALGORITHMS.items():
        check(f"{case['fixture']} {algorithm}", name(digest_of(bytes_)), case["body"][algorithm])

    columns = TABLES[case["table"]]
    check(f"{case['label']} columns of {case['table']}", set(case["summary"]), columns)

    if case["table"] == "mail_summary":
        check(f"{case['label']} size column", case["summary"]["size"], case["body"]["len"])
        require(f"{case['label']} in_reply_to is an array", isinstance(case["summary"]["in_reply_to"], list))

    for address in case["addresses"]:
        require(f"{case['label']} role {address['role']}", address["role"] in ROLES)
        check(f"{case['label']} address {address['address']} canonical", address["address"], address["address"].lower())

    if "hint" in case:
        minted = f"dup:{case['hint']}#{case['handle']}"
        check(f"{case['label']} minted link_id", minted, case["link_id"])

# The sync cases (SYNC.md section 11): shape and references only.
sync_cases = sorted((root / "sync").glob("*.json"))

for path in sync_cases:
    case = json.loads(path.read_text())
    label = path.name
    for key in ("label", "store", "run", "remote", "expect"):
        require(f"{label}: has {key}", key in case)
    store = case["store"]
    labels = set(store.get("objects", {}))
    for object_label, spec in store.get("objects", {}).items():
        require(f"{label}: object {object_label} names a fixture", (root / spec["body"]).is_file())
    collections = {c["id"] for c in store.get("collections", [])}
    for item in store.get("items", []) + case["expect"].get("store", {}).get("items", []):
        require(f"{label}: item {item['link_id']} in a known collection", item["collection"] in collections)
        require(f"{label}: item {item['link_id']} names a known object", item.get("object") in labels | {None})
    for binding in store.get("bindings", []) + case["expect"].get("store", {}).get("bindings", []):
        require(f"{label}: binding {binding['handle']} names a known base", binding.get("base_object") in labels | {None})
    require(f"{label}: run names a verb", case["run"].get("verb") in {"open", "sync", "upgrade", "mutate", "rekey"})

# The search cases (SEARCH.md section 11): every fixture and placement resolves.
search = root / "search"
store = json.loads((search / "store.json").read_text())
queries = json.loads((search / "queries.json").read_text())
placements = {(item["collection"], item["seq"]) for item in store["items"]}
accounts = {c["id"]: c["account"] for c in store["collections"]}
hits = {(accounts[item["collection"]], item["seq"]) for item in store["items"]}

for item in store["items"]:
    require(f"search store: {item['link_id']} in a known collection", item["collection"] in accounts)
    if "fixture" in item:
        require(f"search store: {item['fixture']} exists", (root / item["fixture"]).is_file())

for case in queries["cases"]:
    for hit in case["hits"]:
        require(f"search {case['query']!r}: hit {hit} exists", tuple(hit) in hits)

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print(
    f"{len(objects['base32']['cases'])} base32 cases, "
    f"{len(objects['objects'])} object names, "
    f"{len(summaries['cases'])} summaries over {len(fixtures)} fixtures, "
    f"{sum('hint' in case for case in summaries['cases'])} minted link ids, "
    f"{len(sync_cases)} sync cases and {len(queries['cases'])} search cases check"
)
