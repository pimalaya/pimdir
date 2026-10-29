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
import re
import sys
from datetime import date
from email import message_from_bytes
from email.header import decode_header, make_header
from pathlib import Path
from urllib.parse import unquote

from blake3 import blake3

ALGORITHMS = {
    "blake3": lambda body: blake3(body).digest(),
    "sha256-128": lambda body: hashlib.sha256(body).digest()[:16],
}

TABLES = {
    "mail_summary": {"message_id", "in_reply_to", "subject", "sender", "sender_name", "date", "size", "attachment", "invitation"},
    "contact_summary": {"uid", "fn", "kind", "org"},
    "event_summary": {"uid", "summary", "location", "dtstart", "dtstart_tzid", "dtstart_value", "dtend", "recurring", "until"},
    "task_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value", "due", "due_tzid", "due_value", "status", "completed", "percent", "recurring", "until", "priority", "categories", "parent", "mid"},
    "journal_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value"},
}

FILE_SUMMARY = {"name", "media_type", "size", "part"}

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


def fnv1a(data):
    """FNV-1a 64 as sixteen hex digits: the hash: key of Annex A.2 over the
    bytes whole, the change key of SYNC.md section 4 over fields each
    followed by one NUL."""
    digest = 0xCBF29CE484222325
    for byte in data:
        digest ^= byte
        digest = (digest * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % digest


def change_key(collection, push):
    """The idempotency key SYNC.md section 4 derives for one expected push.
    An object is keyed by its blake3 name, the algorithm the vectors' stores
    are built under."""

    def option(value):
        return [b"1", value.encode()] if value is not None else [b"0"]

    def flags(value):
        if value is None:
            return [b"unknown"]
        return [b"known", str(len(value)).encode()] + [flag.encode() for flag in sorted(value)]

    fields = [collection.encode(), push["handle"].encode()]
    kind = push["kind"]
    if kind == "Add":
        fields += [b"add"] + option(push.get("link_id")) + flags(push.get("flags"))
        origin = push.get("origin")
        fields += [b"1", origin["collection"].encode(), origin["handle"].encode()] if origin else [b"0"]
        fields += option(push.get("object"))
    elif kind == "Remove":
        fields += [b"remove"] + option(push.get("to"))
    elif kind == "SetFlags":
        fields += [b"set-flags"] + flags(push.get("flags"))
    elif kind == "Update":
        fields += [b"update", push["object"].encode()]
    return fnv1a(b"".join(field + b"\x00" for field in fields))


def body(case):
    """A case's bytes, spelled out in hex or generated from its pattern."""
    if "body_hex" in case:
        return bytes.fromhex(case["body_hex"])
    return bytes(i % 251 for i in range(case["body_len"]))


# The query language of SEARCH.md section 8.3, read from the prose, so every
# refusal case's code and span, and every other case's query, is checked
# against the grammar rather than against an implementation.
TEXT_FIELDS = {
    "subject", "title", "summary", "body", "from", "to", "cc", "bcc", "attendee", "organizer",
    "email", "with", "person", "attachment", "mimetype", "location",
}
CLOSED_FIELDS = {
    "kind": {"mail", "contact", "event", "task", "journal", "file"},
    "is": {"unread", "read", "flagged", "answered", "draft", "encrypted"},
    "has": {"body", "attachment"},
    "status": {"needs-action", "in-process", "completed", "cancelled"},
    "priority": {"high", "medium", "low", "none"},
}
DATE_FIELDS = {"date", "when"}
OPEN_FIELDS = {"tag", "flag", "account", "collection", "folder", "thread", "id", "linked", "category"}
FIELDS = TEXT_FIELDS | set(CLOSED_FIELDS) | DATE_FIELDS | {"changed"} | OPEN_FIELDS
CODES = {
    "empty-query", "unknown-field", "invalid-value", "invalid-date", "unterminated-phrase",
    "unbalanced-parenthesis", "dangling-operator", "invalid-wildcard",
}
WHITESPACE = " \t\r\n"


class Refused(Exception):
    def __init__(self, code, start, end):
        super().__init__(code)
        self.code, self.start, self.end = code, start, end


def lex(query):
    """The tokens, in reading order: "(", ")", a phrase, an operator, a term
    or a field term, each with its span in characters."""
    tokens, at = [], 0
    while at < len(query):
        char = query[at]
        if char in WHITESPACE:
            at += 1
        elif char in "()":
            tokens.append({"kind": char, "start": at, "end": at + 1})
            at += 1
        elif char == "-":
            # A `-` beginning a primary is `not`; one followed by whitespace, a
            # `)` or the end has nothing to negate.
            bare = at + 1 == len(query) or query[at + 1] in WHITESPACE + ")"
            tokens.append({"kind": "operator", "start": at, "end": at + 1, "word": "not", "bare": bare})
            at += 1
        elif char == '"':
            close = query.find('"', at + 1)
            if close < 0:
                raise Refused("unterminated-phrase", at, len(query))
            tokens.append({"kind": "phrase", "start": at, "end": close + 1})
            at = close + 1
        else:
            end = at
            while end < len(query) and query[end] not in WHITESPACE + '()"':
                end += 1
            colon = query.find(":", at, end)
            if colon < 0:
                word = query[at:end]
                kind = "operator" if word.lower() in {"and", "or", "not"} else "text"
                tokens.append({"kind": kind, "start": at, "end": end, "word": word.lower()})
                at = end
                continue
            token = {"kind": "field", "start": at, "end": end, "colon": colon, "phrase": False}
            # A field whose value is a phrase: the phrase right after the colon.
            if colon == end - 1 and end < len(query) and query[end] == '"':
                close = query.find('"', end + 1)
                if close < 0:
                    raise Refused("unterminated-phrase", end, len(query))
                token.update(end=close + 1, phrase=True)
            tokens.append(token)
            at = token["end"]
    return tokens


def check_wildcard(word, offset, allowed):
    """A `*` only as the last character, after two or more."""
    star = word.find("*")
    if star >= 0 and not (allowed and star == len(word) - 1 and star >= 2):
        raise Refused("invalid-wildcard", offset + star, offset + star + 1)


def date_point(value):
    if re.fullmatch(r"\d{4}", value) or value in {"today", "yesterday"} or re.fullmatch(r"\d+[dwy]", value):
        return True
    if re.fullmatch(r"\d{4}-\d{2}", value):
        return 1 <= int(value[5:]) <= 12
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        try:
            date.fromisoformat(value)
            return True
        except ValueError:
            return False
    return False


def range_of(value, point):
    if ".." not in value:
        return point(value)
    low, high = value.split("..", 1)
    return (low or high) != "" and all(side == "" or point(side) for side in (low, high))


def check_term(query, token):
    if token["kind"] == "text":
        check_wildcard(query[token["start"]:token["end"]], token["start"], True)
        return
    if token["kind"] != "field":
        return
    start, colon, end = token["start"], token["colon"], token["end"]
    name = query[start:colon]
    if name not in FIELDS:
        raise Refused("unknown-field", start, colon + 1)
    if end == colon + 1:
        raise Refused("invalid-value", start, end)
    value = query[colon + 2:end - 1] if token["phrase"] else query[colon + 1:end]
    if not token["phrase"]:
        check_wildcard(value, colon + 1, name in TEXT_FIELDS and "@" not in value)
    if name in CLOSED_FIELDS and value not in CLOSED_FIELDS[name]:
        raise Refused("invalid-value", colon + 1, end)
    if name in DATE_FIELDS and not range_of(value, date_point):
        raise Refused("invalid-date", colon + 1, end)
    if name == "changed" and not range_of(value, lambda side: side.isascii() and side.isdigit()):
        raise Refused("invalid-value", colon + 1, end)


def parse(query):
    """Raises Refused with the fault the first pass to find one answers:
    the phrases, the parentheses, then the terms and operators in reading
    order."""
    tokens = lex(query)
    if not tokens:
        raise Refused("empty-query", 0, len(query))
    opened, faults = [], []
    for token in tokens:
        if token["kind"] == "(":
            opened.append(token["start"])
        elif token["kind"] == ")":
            if opened:
                opened.pop()
            else:
                faults.append(token["start"])
    if faults or opened:
        first = min(faults + opened)
        raise Refused("unbalanced-parenthesis", first, first + 1)

    at = 0

    def peek():
        return tokens[at] if at < len(tokens) else None

    def operator(token, *words):
        return token is not None and token["kind"] == "operator" and token["word"] in words

    def take():
        nonlocal at
        at += 1
        return tokens[at - 1]

    def dangling(token):
        return Refused("dangling-operator", token["start"], token["end"])

    def disjunction(expected_by):
        conjunction(expected_by)
        while operator(peek(), "or"):
            conjunction(take())

    def conjunction(expected_by):
        negation(expected_by)
        while True:
            token = peek()
            if operator(token, "and"):
                negation(take())
            elif token is not None and (token["kind"] in {"(", "phrase", "text", "field"} or operator(token, "not")):
                negation(None)
            else:
                return

    def negation(expected_by):
        first = None
        while operator(peek(), "not"):
            token = take()
            if token.get("bare"):
                raise dangling(token)
            first = first or token
        primary(first or expected_by)

    def primary(expected_by):
        token = peek()
        if token is None or token["kind"] == ")" or operator(token, "and", "or"):
            raise dangling(expected_by or token)
        take()
        if token["kind"] == "(":
            if peek()["kind"] == ")":
                raise Refused("empty-query", token["start"], peek()["end"])
            disjunction(None)
            take()
        else:
            check_term(query, token)

    disjunction(None)

# The temporal coverage of SEARCH.md section 8.2, re-derived for a case whose
# query is only `collection:`, `account:` and absolute `date:` terms: every
# collection in scope rolled up from its sources' coverage (STORAGE section
# 10), the highest floor above the range's start, the lowest ceiling below its
# end, filling if a source never closed a round.
def span_of(point):
    if re.fullmatch(r"\d{4}", point):
        return f"{point}-01-01T00:00:00Z", f"{int(point) + 1}-01-01T00:00:00Z"
    if re.fullmatch(r"\d{4}-\d{2}", point):
        year, month = int(point[:4]), int(point[5:])
        after = f"{year + month // 12}-{month % 12 + 1:02d}"
        return f"{point}-01T00:00:00Z", f"{after}-01T00:00:00Z"
    return None


def temporal_of(query, collections):
    scope, since, until = list(collections), None, None
    for word in query.split():
        name, _, value = word.partition(":")
        if name == "collection":
            scope = [c for c in scope if c["id"] == value]
        elif name == "account":
            scope = [c for c in scope if c["account"] == value]
        elif name == "date":
            low, _, high = value.partition("..") if ".." in value else (value, "", value)
            low_span, high_span = (span_of(low) if low else (None, None)), (span_of(high) if high else (None, None))
            if low_span is None or high_span is None:
                return None
            since, until = low_span[0], high_span[1]
        else:
            return None
    floor = ceiling = None
    filling = False
    for collection in scope:
        for source in collection.get("sources", []):
            if source["covered_at"] is None:
                filling = True
                continue
            low, high = source["covered_since"], source["covered_until"]
            if low is not None and (since is None or since < low) and (floor is None or low > floor):
                floor = low
            if high is not None and (until is None or until > high) and (ceiling is None or high < ceiling):
                ceiling = high
    if floor is None and ceiling is None and not filling:
        return "full"
    return {"since": floor, "until": ceiling, "filling": filling}


# The chunk boundaries of SEARCH.md section 6, over a field's text as bytes.
BLANK_LINES = re.compile(rb"\r?\n(?:[ \t]*\r?\n)+")
CHUNK_BYTES = 1024


def chunk(text):
    paragraphs, at = [], 0
    for run in BLANK_LINES.finditer(text):
        if run.start() > at:
            paragraphs.append((at, run.start()))
        at = run.end()
    if len(text) > at:
        paragraphs.append((at, len(text)))
    chunks, current = [], None
    for start, end in paragraphs:
        while True:
            if current is not None and end - current[0] <= CHUNK_BYTES:
                current = (current[0], end)
                break
            if current is not None:
                chunks.append(current)
                current = None
            if end - start <= CHUNK_BYTES:
                current = (start, end)
                break
            window = text[start:start + CHUNK_BYTES]
            space = max(window.rfind(byte) for byte in (b" ", b"\t", b"\r", b"\n"))
            if space >= 0:
                cut = start + space + 1
            else:
                cut = start + CHUNK_BYTES
                while text[cut] & 0xC0 == 0x80:
                    cut -= 1
            chunks.append((start, cut))
            start = cut
    if current is not None:
        chunks.append(current)
    return chunks


def task_columns(bytes_):
    """The task columns Annex A.4 reads without the body, by a second path:
    the VTODO's lines unfolded and split by hand, nothing but the stdlib."""
    text = bytes_.decode().replace("\r\n ", "").replace("\r\n\t", "")
    lines = text.split("\r\n")
    inside = lines[lines.index("BEGIN:VTODO") + 1:lines.index("END:VTODO")]
    priority, categories, parent, mid = None, [], None, None
    for line in inside:
        head, value = line.split(":", 1)
        prop, *params = head.split(";")
        prop = prop.upper()
        if prop == "PRIORITY" and priority is None:
            priority = int(value) if value.isdigit() and int(value) <= 9 else None
        elif prop == "CATEGORIES":
            for raw in re.split(r"(?<!\\),", value):
                decoded = re.sub(r"\\([\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), raw)
                if decoded:
                    categories.append(decoded)
        elif prop == "RELATED-TO" and parent is None:
            types = [p.split("=", 1)[1].upper() for p in params if p.upper().startswith("RELTYPE=")]
            if not types or types[0] == "PARENT":
                parent = value
        elif prop in ("ATTACH", "URL") and mid is None and value.lower().startswith("mid:"):
            mid = unquote(value[4:].split("/", 1)[0])
    return {"priority": priority, "categories": categories, "parent": parent, "mid": mid}


def text_of(parts):
    return "".join(part if isinstance(part, str) else part["repeat"] * part["times"] for part in parts).encode()



def attachments(message):
    """The parts a message stands for as files: those carrying
    Content-Disposition: attachment, by IMAP section (RFC 3501 section
    6.4.5), the message itself 1 when it is no multipart, a multipart's
    children numbered under it, a message/rfc822 part one part. The name is
    the filename, else the Content-Type name, RFC 2231 and RFC 2047 decoded;
    the media type NULL when no Content-Type is stated; the size the
    transfer-decoded octets."""

    def stated(part, section):
        name = part.get_filename() or ""
        if "=?" in name:
            name = str(make_header(decode_header(name)))
        media_type = part.get_content_type() if part.get("Content-Type") is not None else None
        size = None if part.get_content_maintype() == "multipart" else len(part.get_payload(decode=True))
        return {"part": section, "name": name, "media_type": media_type, "size": size}

    def walk(part, prefix, found):
        for at, child in enumerate(part.get_payload(), 1):
            section = f"{prefix}{at}"
            if child.get_content_disposition() == "attachment":
                found.append(stated(child, section))
            if child.get_content_maintype() == "multipart":
                walk(child, f"{section}.", found)
        return found

    if message.get_content_maintype() != "multipart":
        return [stated(message, "1")] if message.get_content_disposition() == "attachment" else []
    return walk(message, "", [])


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
        # The mark without the body (Annex A.1): 1 when the top-level
        # Content-Type is multipart/mixed, else 0, read by the stdlib parser.
        mixed = message_from_bytes(bytes_).get_content_type() == "multipart/mixed"
        check(f"{case['label']} meta_attachment", case.get("meta_attachment"), int(mixed))
        # The invitation: the UID of the first component of the first
        # text/calendar part, unfolded, read by the stdlib parser.
        invitation = None
        for part in message_from_bytes(bytes_).walk():
            if part.get_content_type() == "text/calendar":
                text = part.get_payload(decode=True).decode().replace("\r\n ", "").replace("\r\n\t", "")
                uids = [line.split(":", 1)[1] for line in text.split("\r\n")
                        if ":" in line and line.split(":", 1)[0].split(";")[0].upper() == "UID"]
                invitation = uids[0] if uids else None
                break
        check(f"{case['label']} invitation", case["summary"]["invitation"], invitation)
        # The stand-ins' parts (STORAGE section 14.3, Annex A.7), read by the
        # stdlib parser.
        check(f"{case['label']} attachments", case.get("attachments"), attachments(message_from_bytes(bytes_)))

    for address in case["addresses"]:
        require(f"{case['label']} role {address['role']}", address["role"] in ROLES)
        check(f"{case['label']} address {address['address']} canonical", address["address"], address["address"].lower())

    if "hint" in case:
        minted = f"dup:{case['hint']}#{case['handle']}"
        check(f"{case['label']} minted link_id", minted, case["link_id"])

    if case["summary"].get("uid") is None and case["table"] != "mail_summary":
        check(f"{case['label']} hash: link_id", case["link_id"], "hash:" + fnv1a(bytes_))

    if case["table"] == "mail_summary" and case["summary"]["message_id"] is None and "hint" not in case:
        row = case["summary"]
        alt = "alt:" + "|".join(row[column] or "" for column in ("subject", "date", "sender"))
        check(f"{case['label']} alt: link_id", case["link_id"], alt)

    if case["table"] == "task_summary":
        check(f"{case['label']} task columns", {
            column: case["summary"][column] for column in ("priority", "categories", "parent", "mid")
        }, task_columns(bytes_))


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
    # A run may declare a collection, as an owner recording attachments
    # declares the account's (STORAGE section 14.3).
    expected = case["expect"].get("store", {})
    declared = store.get("collections", []) + expected.get("collections", [])
    collections = {c["id"] for c in declared}
    for collection in declared:
        if collection.get("role") == "attachments":
            require(f"{label}: the attachments role marks a file collection", collection["kind"] == "application/octet-stream")
    for item in store.get("items", []) + expected.get("items", []):
        require(f"{label}: item {item['link_id']} in a known collection", item["collection"] in collections)
    # An expected reference names two ends the expected store holds (STORAGE
    # section 14.2).
    kinds = {c["id"]: c["kind"] for c in declared}
    held = {(kinds.get(item["collection"]), item["link_id"]) for item in expected.get("items", [])}
    for reference in expected.get("references", []):
        for end in ("from", "to"):
            endpoint = (reference[f"{end}_kind"], reference[f"{end}_link_id"])
            require(f"{label}: reference {end} {endpoint} is held", endpoint in held)
        require(f"{label}: item {item['link_id']} names a known object", item.get("object") in labels | {None})
    for binding in store.get("bindings", []) + case["expect"].get("store", {}).get("bindings", []):
        require(f"{label}: binding {binding['handle']} names a known base", binding.get("base_object") in labels | {None})
    # A supersession pairs two items the store holds, the superseded one a
    # tombstone (STORAGE sections 4.3 and 15.3).
    for rows, side in ((store, "store"), (expected, "expected store")):
        items = {(item["collection"], item["link_id"]): item for item in rows.get("items", [])}
        for pair in rows.get("supersessions", []):
            require(f"{label}: {side} supersession names its columns", set(pair) == {"collection", "link_id", "by_collection", "by_link_id"})
            superseded = items.get((pair.get("collection"), pair.get("link_id")))
            require(f"{label}: {side} supersession names a held tombstone", superseded is not None and superseded.get("deleted") == 1)
            require(f"{label}: {side} supersession names a held superseding item", (pair.get("by_collection"), pair.get("by_link_id")) in items)
    require(f"{label}: run names a verb", case["run"].get("verb") in {"open", "sync", "upgrade", "mutate", "rekey"})
    if case["run"].get("verb") == "mutate":
        require(f"{label}: a mutate run carries its mutation", isinstance(case["run"].get("mutation"), dict))
    require(f"{label}: no delete policy option, the engine decides per item", "delete" not in case["run"].get("options", {}))
    require(f"{label}: no probes, every member arriving named", "probes" not in store and "probes" not in case["expect"].get("store", {}))
    scope = case["run"].get("options", {}).get("scope")
    if scope is not None:
        require(f"{label}: a scope bounds a mail collection", all(c["kind"] == "message/rfc822" for c in store.get("collections", [])))
        require(f"{label}: a scope is since and until", set(scope) == {"since", "until"})

    # What a connector answers (SYNC.md section 4): one page as `snapshot`,
    # or `pages`, newest first, every page but the last carrying a cursor.
    # Every member carries its meta, read from a fixture: nothing reaches the
    # store unnamed.
    remote = case["remote"]
    require(f"{label}: one snapshot or pages, not both", not (remote.get("snapshot") and remote.get("pages")))
    pages = remote.get("pages") or ([remote["snapshot"]] if remote.get("snapshot") else [])
    for at, page in enumerate(remote.get("pages") or []):
        require(f"{label}: page {at} says whether it is the last", isinstance(page.get("last"), bool))
        require(f"{label}: page {at} carries a cursor unless it is the last", page.get("last") or page.get("cursor") is not None)
    # A head (SYNC.md sections 4 and 5): listed only to resume an open round,
    # of a kind the connector lists; a delta head asked from the round's
    # checkpoint, or a band round's from the source's, and carrying the
    # checkpoint it lands; a band head asked from the instant the round
    # opened, stating no removal and carrying no checkpoint.
    head = remote.get("head")
    if head is not None:
        kind = head.get("kind")
        require(f"{label}: a head is a delta or a band head", kind in {"delta", "band"})
        require(f"{label}: a {kind} head is one the connector lists", kind in remote.get("heads", []))
        row = next((s for s in store.get("sources", [])
                    if s["collection"] == case["run"]["collection"] and s["source"] == case["run"]["source"]), {})
        require(f"{label}: a head resumes an open round", row.get("round_open") is True)
        if kind == "delta":
            position = row.get("round_checkpoint") or (row.get("checkpoint") if row.get("round_band") else None)
            require(f"{label}: a delta head lists from the round's checkpoint, or a band round's from the source's", position is not None and head.get("from") == position)
            require(f"{label}: a delta head carries the checkpoint it lands", bool(head.get("rejected")) or head.get("checkpoint") is not None)
        if kind == "band":
            require(f"{label}: a band head lists from the instant the round opened", head.get("since") is not None and head.get("since") == row.get("round_started_at"))
            require(f"{label}: a band head carries no checkpoint and states no removal", head.get("checkpoint") is None and not head.get("vanished") and not head.get("rejected"))
        if not head.get("rejected"):
            pages = [head] + pages
    files = all(c["kind"] == "application/octet-stream" for c in store.get("collections", []))
    for page in pages:
        for member in page["items"]:
            meta = member.get("meta")
            if files:
                # A file's meta is what its source states (Annex A.7): its
                # stable id and its summary, no body.
                require(f"{label}: file member {member['handle']} states its key and summary", isinstance(meta, dict) and set(meta) == {"link_id", "summary"})
                require(f"{label}: file member {member['handle']} summary is file_summary's", set(meta.get("summary", {})) == FILE_SUMMARY)
                continue
            require(f"{label}: member {member['handle']} carries its meta", isinstance(meta, dict) and (root / meta.get("body", "")).is_file())
            # A meta is read off the fixture save what a source states
            # itself: its attachment flag and its size (Annex A.1).
            require(f"{label}: member {member['handle']} meta is body, attachment and size", set(meta) <= {"body", "attachment", "size"})
            require(f"{label}: member {member['handle']} states a size in octets", isinstance(meta.get("size", 0), int))
    for source in store.get("sources", []) + case["expect"].get("store", {}).get("sources", []):
        if source.get("round_open") is False:
            require(f"{label}: a closed round carries no cursor", source.get("round_cursor") is None and source.get("round_checkpoint") is None)
            require(f"{label}: a closed round lists no band", source.get("round_band") in (None, False))
        if source.get("covered") is False:
            require(f"{label}: no coverage carries no bound", source.get("covered_since") is None and source.get("covered_until") is None)

    # A sync never deletes on the server on its own account (SYNC.md section
    # 5): every Remove pushed names a handle the consumer tombstoned, a
    # binding of a deleted item, or the one a mutate run removes.
    staged = {
        binding["handle"]
        for binding in store.get("bindings", [])
        for item in store.get("items", [])
        if item["collection"] == binding["collection"] and item["link_id"] == binding["link_id"] and item.get("deleted") == 1
    }
    if case["run"].get("verb") == "mutate" and case["run"]["mutation"].get("kind") == "Remove":
        staged |= {binding["handle"] for binding in store.get("bindings", [])}
    for push in case["expect"].get("pushes", []):
        if push.get("kind") == "Remove":
            require(f"{label}: Remove {push['handle']} was staged by the consumer", push["handle"] in staged)
    for binding in store.get("bindings", []) + case["expect"].get("store", {}).get("bindings", []):
        provisional = binding["handle"].startswith("\u0001")
        require(f"{label}: binding {binding['handle']!r} is provisional iff it has no base", provisional == (binding.get("base_present", 0) == 0))
        if provisional:
            check(f"{label}: provisional handle of {binding['link_id']}", binding["handle"], "\u0001" + binding["link_id"])

    # Every push is keyed as SYNC.md section 4 says, its object named under
    # blake3 for the derivation, so an engine's keys are checked against the
    # prose and never against another engine.
    names = {object_label: name(blake3((root / spec["body"]).read_bytes()).digest()) for object_label, spec in store.get("objects", {}).items()}
    for push in case["expect"].get("pushes", []):
        require(f"{label}: push {push.get('handle')} names a kind", push.get("kind") in {"Add", "Remove", "SetFlags", "Update"})
        require(f"{label}: push {push.get('handle')} carries a key", "key" in push)
        resolved = dict(push)
        if resolved.get("object") is not None:
            require(f"{label}: push {push['handle']} names a known object", push["object"] in names)
            resolved["object"] = names.get(push["object"], push["object"])
        check(f"{label}: push {push.get('handle')} key", push.get("key"), change_key(case["run"]["collection"], resolved))
    for outcome in case["expect"].get("outcomes", []):
        require(f"{label}: outcome {outcome.get('handle')} is Accepted or Rejected", outcome.get("outcome") in {"Accepted", "Rejected"})

# The search cases (SEARCH.md section 11): every fixture and placement resolves.
search = root / "search"
store = json.loads((search / "store.json").read_text())
queries = json.loads((search / "queries.json").read_text())
placements = {(item["collection"], item["seq"]) for item in store["items"]}
accounts = {c["id"]: c["account"] for c in store["collections"]}
hits = {(accounts[item["collection"]], item["seq"]) for item in store["items"]}

# A source's coverage row (STORAGE section 10): never closed carries no bound.
for collection in store["collections"]:
    for source in collection.get("sources", []):
        require(f"search store: {collection['id']} source {source.get('source')} states its coverage",
                set(source) == {"source", "covered_since", "covered_until", "covered_at"})
        if source.get("covered_at") is None:
            require(f"search store: {collection['id']} never closed, so no bound",
                    source.get("covered_since") is None and source.get("covered_until") is None)

for item in store["items"]:
    require(f"search store: {item['link_id']} in a known collection", item["collection"] in accounts)
    if "fixture" in item:
        require(f"search store: {item['fixture']} exists", (root / item["fixture"]).is_file())

# A reference names two endpoints the store holds (STORAGE section 14.2), each
# a kind and a link id with an item under that kind.
kinds = {c["id"]: c["kind"] for c in store["collections"]}
endpoints = {(kinds[item["collection"]], item["link_id"]) for item in store["items"]}
for reference in store.get("references", []):
    for end in ("from", "to"):
        endpoint = (reference[f"{end}_kind"], reference[f"{end}_link_id"])
        require(f"search store: reference {end} {endpoint} is held", endpoint in endpoints)

# A case answers hits, a threaded listing or a refusal (SEARCH.md section 11),
# and the grammar above accepts its query or refuses it as the case says.
KEYS = {"query", "hits", "threads", "error", "sort", "ordered", "horizon_left", "temporal", "note"}
for case in queries["cases"]:
    label = f"search {case['query']!r}"
    require(f"{label}: known keys only", set(case) <= KEYS)
    answers = [key for key in ("hits", "threads", "error") if key in case]
    require(f"{label}: answers one of hits, threads or error", len(answers) == 1)
    require(f"{label}: a known sort", case.get("sort", "date") in {"date", "name", "relevance"})
    require(f"{label}: ordered and horizon_left are booleans",
            isinstance(case.get("ordered", False), bool) and isinstance(case.get("horizon_left", False), bool))
    for hit in case.get("hits", []) + [hit for thread in case.get("threads", []) for hit in thread["hits"]]:
        require(f"{label}: hit {hit} exists", tuple(hit) in hits)
    for thread in case.get("threads", []):
        require(f"{label}: thread {thread.get('thread')} states its id, count, first and last",
                set(thread) == {"thread", "count", "first", "last", "hits"} and thread["first"] <= thread["last"])
    temporal = case.get("temporal")
    if temporal is not None:
        require(f"{label}: temporal is full or bounded",
                temporal == "full" or (isinstance(temporal, dict) and set(temporal) == {"since", "until", "filling"}))
        derived = temporal_of(case["query"], store["collections"])
        require(f"{label}: a temporal case is one checks/vectors.py re-derives", derived is not None)
        check(f"{label}: temporal", temporal, derived)
    try:
        parse(case["query"])
        got = None
    except Refused as refused:
        got = {"code": refused.code, "start": refused.start, "end": refused.end}
    if "error" in case:
        require(f"{label}: refusals carry no sort, order or coverage", not set(case) & {"sort", "ordered", "horizon_left", "temporal"})
        require(f"{label}: a known code", case["error"].get("code") in CODES)
        check(f"{label}: refusal", got, case["error"])
    else:
        check(f"{label}: accepted", got, None)

# The GTD views (GUIDE.md section 17): each query of the guide's table is a
# case, and its hits are re-derived from the fixtures' bytes, a task's status
# and categories read by task_columns' second path, never by the query.
def task_state(bytes_):
    text = bytes_.decode().replace("\r\n ", "").replace("\r\n\t", "")
    status = next((line.split(":", 1)[1].upper() for line in text.split("\r\n")
                   if line.split(":", 1)[0].split(";")[0].upper() == "STATUS"), None)
    return status, {category.lower() for category in task_columns(bytes_)["categories"]}

RESERVED = {"inbox", "waiting", "someday"}
VIEWS = {
    "Inbox": lambda categories: "inbox" in categories,
    "Waiting": lambda categories: "waiting" in categories,
    "Someday": lambda categories: "someday" in categories,
    "Next": lambda categories: not categories & RESERVED,
}
guide = (root.parent / "GUIDE.md").read_text().split("## 17. Tasks by categories")[1].split("\n## ")[0]
view_queries = dict(re.findall(r"^\| (\w+) \| `([^`]+)` \|$", guide, re.M))
check("gtd views: the guide's table names the four", sorted(view_queries), sorted(VIEWS))
tasks = []
for item in store["items"]:
    if "fixture" in item:
        bytes_ = (root / item["fixture"]).read_bytes()
        if b"BEGIN:VTODO" in bytes_:
            tasks.append(((accounts[item["collection"]], item["seq"]), *task_state(bytes_)))
cases = {case["query"]: case for case in queries["cases"]}
for view, query in view_queries.items():
    require(f"gtd view {view}: {query!r} is a case", query in cases and "hits" in cases.get(query, {}))
    derived = sorted([*key] for key, status, categories in tasks
                     if status not in ("COMPLETED", "CANCELLED") and VIEWS.get(view, lambda _: False)(categories))
    if query in cases:
        check(f"gtd view {view}: hits", sorted(cases[query].get("hits", [])), derived)

# Every field of SEARCH.md section 8's table, read from the table, is the
# parser's and is used by at least one answered case, so a field the compiler
# maps wrong fails a case rather than a user.
table = (root.parent / "SEARCH.md").read_text().split("| Field | Meaning |")[1].split("\n\n")[0]
documented = {name for line in table.splitlines()[2:] for name in re.findall(r"`([a-z]+):", line.split("|")[1])}
check("search fields: the grammar's are the table's", sorted(FIELDS), sorted(documented))
answered = set()
for case in queries["cases"]:
    if "error" not in case:
        answered |= {token["kind"] == "field" and case["query"][token["start"]:token["colon"]] for token in lex(case["query"])}
for field in sorted(documented - answered):
    failures.append(f"search field {field}: used by no hits or threads case")

# The task writers (GUIDE.md section 17): every case's shape and references,
# and what its edit may change, re-derived from the bytes on both sides by a
# second path, so an expected fixture that touches a line the guide keeps, or
# writes a state or a category the edit did not ask for, fails here.
GTD_STAMPED = {"DTSTAMP", "LAST-MODIFIED"}
GTD_OPS = {"set-state", "set-categories", "set-contact", "capture", "captured-at"}
GTD_EXPECT = {"bytes", "unchanged", "refused", "vtodo", "value"}


def gtd_groups(bytes_):
    """The VTODO's properties as (name, params, value, raw bytes), a folded
    line one group, nested components (an alarm) kept as their raw lines."""
    require("gtd writers: a fixture is CRLF throughout", b"\n" not in bytes_.replace(b"\r\n", b""))
    physical = bytes_.split(b"\r\n")
    groups = []
    for line in physical:
        if line[:1] in (b" ", b"\t") and groups:
            groups[-1] += b"\r\n" + line
        else:
            groups.append(line)
    begin, end = groups.index(b"BEGIN:VTODO"), groups.index(b"END:VTODO")
    require("gtd writers: a fixture holds one VTODO", groups.count(b"BEGIN:VTODO") == 1)
    out, depth = [], 0
    for raw in groups[begin + 1:end]:
        text = raw.replace(b"\r\n ", b"").replace(b"\r\n\t", b"").decode()
        head, value = re.match(r'^((?:[^:"]|"[^"]*")*):(.*)$', text).groups()
        name, *params = re.findall(r'(?:[^;"]|"[^"]*")+', head)
        name = name.upper()
        if name == "BEGIN":
            depth += 1
        nested = depth > 0
        if name == "END":
            depth -= 1
        out.append(("" if nested else name, params, value, raw))
    return out


def gtd_values(value):
    return [re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), raw)
            for raw in re.split(r"(?<!\\),", value) if raw]


def gtd_categories(groups):
    values = [v for name, _, value, _ in groups if name == "CATEGORIES" for v in gtd_values(value)]
    return [v for v in values if v.lower().strip() in RESERVED], [v for v in values if v.lower().strip() not in RESERVED]


def gtd_person(categories):
    kept = []
    for category in (c.strip() for c in categories):
        if category and all(category.lower() != known.lower() for known in kept):
            kept.append(category)
    return kept


def gtd_contacts(groups):
    return [(value, [p for p in params if p.upper().startswith("ALTREP=")]) for name, params, value, _ in groups if name == "CONTACT"]


def gtd_contact_of(edit):
    address = edit.get("address")
    text = edit.get("name") or address
    return (text, [f'ALTREP="mailto:{address}"'] if address else [])


gtd_dir = root / "gtd"
writers = json.loads((gtd_dir / "writers.json").read_text())
now = writers.get("now", "")
require("gtd writers: now is a UTC instant", re.fullmatch(r"\d{8}T\d{6}Z", now) is not None)
for case in writers["cases"]:
    label = f"gtd writer {case.get('label')!r}"
    edit, expect = case.get("edit", {}), case.get("expect", {})
    op = edit.get("op")
    require(f"{label}: a known edit", op in GTD_OPS)
    require(f"{label}: one known expectation", len(set(expect) & GTD_EXPECT) == 1 and set(expect) <= GTD_EXPECT | {"names"})
    if op == "capture":
        require(f"{label}: a capture reads no input", "input" not in case)
        lines = set(expect.get("vtodo", []))
        for line in (f"CREATED:{now}", f"DTSTAMP:{now}", "CATEGORIES:inbox", f"SUMMARY:{edit.get('summary')}"):
            require(f"{label}: the capture holds {line}", line in lines)
        require(f"{label}: the capture states a UID", "UID" in expect.get("names", []))
        continue
    require(f"{label}: its input is a fixture", (gtd_dir / case.get("input", "")).is_file())
    before = gtd_groups((gtd_dir / case["input"]).read_bytes())
    reserved, person = gtd_categories(before)
    if op == "captured-at":
        stamps = {name: value for name, _, value, _ in before if name in ("CREATED", "DTSTAMP")}
        check(f"{label}: captured at", expect.get("value"), stamps.get("CREATED", stamps.get("DTSTAMP")))
        continue
    state = edit.get("state")
    wanted = gtd_person(edit.get("categories", []))
    noop = {
        "set-state": {r.lower().strip() for r in reserved} == ({state} if state else set()),
        "set-categories": person == wanted,
        "set-contact": gtd_contacts(before) == [gtd_contact_of(edit)],
    }[op]
    refused = op == "set-categories" and any(c.lower().strip() in RESERVED for c in wanted)
    check(f"{label}: refused exactly when a reserved value is asked for", "refused" in expect, refused)
    check(f"{label}: unchanged exactly when the edit is a no-op", "unchanged" in expect, noop and not refused)
    if "bytes" not in expect:
        continue
    require(f"{label}: its expectation is a fixture", (gtd_dir / expect["bytes"]).is_file())
    after = gtd_groups((gtd_dir / expect["bytes"]).read_bytes())
    touched = {"set-state": {"CATEGORIES"}, "set-categories": {"CATEGORIES"}, "set-contact": {"CONTACT"}}[op] | GTD_STAMPED
    check(f"{label}: every other line kept byte for byte",
          [raw for name, _, _, raw in after if name not in touched], [raw for name, _, _, raw in before if name not in touched])
    stamps = {name: value for name, _, value, _ in after if name in GTD_STAMPED}
    check(f"{label}: DTSTAMP restated", stamps.get("DTSTAMP"), now)
    check(f"{label}: LAST-MODIFIED restated only where carried",
          stamps.get("LAST-MODIFIED"), now if any(name == "LAST-MODIFIED" for name, *_ in before) else None)
    reserved_after, person_after = gtd_categories(after)
    if op == "set-state":
        check(f"{label}: the state", reserved_after, [state] if state else [])
        check(f"{label}: the person's categories kept", person_after, person)
    if op == "set-categories":
        check(f"{label}: the state kept", reserved_after, reserved)
        check(f"{label}: the person's categories", person_after, wanted)
    if op == "set-contact":
        check(f"{label}: one contact", gtd_contacts(after), [gtd_contact_of(edit)])
        check(f"{label}: the categories kept", [raw for name, _, _, raw in after if name == "CATEGORIES"],
              [raw for name, _, _, raw in before if name == "CATEGORIES"])

# The chunk cases (SEARCH.md section 6): every boundary re-derived from the rule.
chunk_cases = json.loads((search / "chunks.json").read_text())["cases"]
for case in chunk_cases:
    derived = []
    for field in ("body", "note"):
        for start, end in chunk(text_of(case["fields"].get(field, []))):
            derived.append({"ord": len(derived), "field": field, "start": start, "end": end})
    check(f"chunks {case['label']!r}", derived, case["chunks"])

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print(
    f"{len(objects['base32']['cases'])} base32 cases, "
    f"{len(objects['objects'])} object names, "
    f"{len(summaries['cases'])} summaries over {len(fixtures)} fixtures, "
    f"{sum('hint' in case for case in summaries['cases'])} minted link ids, "
    f"{len(sync_cases)} sync cases, {len(queries['cases'])} search cases, {len(chunk_cases)} chunk cases and {len(writers['cases'])} task writer cases check"
)
