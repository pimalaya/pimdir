#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Re-derives every value under vectors/ from the bodies it names, and checks
the shape of the sync and search cases nothing but an implementation can run.

The names are checked against the algorithm of STORAGE.md section 5, never
against a store: blake3 and base64 are the second, independent path
vectors/README.md asks for.
"""

import base64
import codecs
import hashlib
import io
import json
import re
import sqlite3
import sys
import unicodedata
from calendar import monthrange
from datetime import date, datetime, timedelta, timezone
from email import message_from_bytes
from email.generator import BytesGenerator
from email.header import decode_header, make_header
from pathlib import Path
from urllib.parse import unquote
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from blake3 import blake3
from jsonschema import Draft202012Validator

# A name (STORAGE section 5): BLAKE3 at 32 bytes in lowercase base32, 52
# characters a path is built from only once they are checked.
NAME = re.compile(r"[a-z2-7]{52}")

TABLES = {
    "mail_summary": {"message_id", "in_reply_to", "subject", "sender", "sender_name", "date", "size", "attachment", "invitation"},
    "contact_summary": {"uid", "fn", "kind", "org"},
    "event_summary": {"uid", "summary", "location", "dtstart", "dtstart_tzid", "dtstart_value", "dtend", "recurring", "until"},
    "task_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value", "due", "due_tzid", "due_value", "status", "completed", "percent", "recurring", "until", "priority", "categories", "parent", "mid", "created"},
    "journal_summary": {"uid", "summary", "dtstart", "dtstart_tzid", "dtstart_value"},
}

FILE_SUMMARY = {"name", "media_type", "size", "part"}
# The prefixes of the keys a writer derives, and the escape (STORAGE section 9).
RESERVED_PREFIXES = ("alt:", "hash:", "dup:", "part:", "file:", "esc:")

ROLES = {"from", "to", "cc", "bcc", "email", "organizer", "attendee", "contact"}
# The closed set of collection kinds (STORAGE section 13), '' undeclared.
KINDS = {"", "message/rfc822", "text/vcard", "text/calendar", "application/octet-stream"}

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
        fields += [b"set-flags"] + flags(push.get("add")) + flags(push.get("remove"))
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
    "has": {"body", "attachment", "phone", "address", "birthday", "photo"},
    "status": {"needs-action", "in-process", "completed", "cancelled"},
    "priority": {"high", "medium", "low", "none"},
}
DATE_FIELDS = {"date", "when"}
OPEN_FIELDS = {"tag", "flag", "account", "collection", "folder", "thread", "id", "linked", "category"}
FIELDS = TEXT_FIELDS | set(CLOSED_FIELDS) | DATE_FIELDS | {"changed"} | OPEN_FIELDS
CODES = {
    "empty-query", "unknown-field", "invalid-value", "invalid-date", "unterminated-phrase",
    "unbalanced-parenthesis", "dangling-operator", "invalid-wildcard", "limit-exceeded",
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
    the length, the phrases, the parentheses with their nesting, then the
    terms and operators in reading order, their count among them. The bounds
    are LIMITS, read from SEARCH.md section 8.3's table."""
    if len(query) > LIMITS["length"]:
        raise Refused("limit-exceeded", LIMITS["length"], len(query))
    tokens = lex(query)
    if not tokens:
        raise Refused("empty-query", 0, len(query))
    opened, faults = [], []
    for token in tokens:
        if token["kind"] == "(":
            if len(opened) == LIMITS["nesting"]:
                faults.append((token["start"], "limit-exceeded"))
            opened.append(token["start"])
        elif token["kind"] == ")":
            if opened:
                opened.pop()
            else:
                faults.append((token["start"], "unbalanced-parenthesis"))
    faults += [(start, "unbalanced-parenthesis") for start in opened]
    if faults:
        first, code = min(faults)
        raise Refused(code, first, first + 1)

    at, terms = 0, 0

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
        nonlocal terms
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
            terms += 1
            if terms > LIMITS["terms"]:
                raise Refused("limit-exceeded", token["start"], token["end"])
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


# Whether a case's date range leaves the horizon (SEARCH.md section 8.1),
# re-derived for a query of plain terms: only a range a calendar item could
# answer leaves it, a query whose kinds or collections hold no calendar
# comparing sort keys alone. None for a query this does not read.
def instant(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def point_span(point, now):
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if point == "today":
        return midnight, midnight + timedelta(days=1)
    if point == "yesterday":
        return midnight - timedelta(days=1), midnight
    amount = re.fullmatch(r"(\d+)([dwy])", point)
    if amount:
        n, unit = int(amount.group(1)), amount.group(2)
        start = now.replace(year=now.year - n) if unit == "y" else now - timedelta(days=n * (7 if unit == "w" else 1))
        return start, now
    low, high = span_of(point) or (None, None)
    if low is None and re.fullmatch(r"\d{4}-\d{2}-\d{2}", point):
        low = f"{point}T00:00:00Z"
        high = (instant(low) + timedelta(days=1)).isoformat().replace("+00:00", "Z")
    return (instant(low), instant(high)) if low else (None, None)


def horizon_left_of(query, collections, now, horizon):
    terms = query.split()
    if any(not re.fullmatch(r"[a-z]+:\S+", term) for term in terms) or "(" in query:
        return None
    kinds, scope, dated = set(), list(collections), None
    for term in terms:
        name, _, value = term.partition(":")
        if name == "kind":
            kinds.add(value)
        elif name in ("collection", "folder"):
            scope = [c for c in scope if c["id"] == value]
        elif name == "account":
            scope = [c for c in scope if c["account"] == value]
        elif name in ("date", "when"):
            dated = value
    if dated is None:
        return None
    calendar = any(c["kind"] == "text/calendar" for c in scope) and (not kinds or kinds & {"event", "task", "journal"})
    low, _, high = dated.partition("..") if ".." in dated else (dated, "", dated)
    start = point_span(low, now)[0] if low else None
    end = point_span(high, now)[1] if high else None
    leaves = start is None or end is None or start < instant(horizon["start"]) or end > instant(horizon["end"])
    return bool(calendar and leaves)


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
    stamps, contacts = {}, []
    for line in inside:
        head, value = split_property(line)
        prop, *params = head.split(";")
        prop = prop.upper()
        if prop in ("CREATED", "DTSTAMP") and prop not in stamps and re.fullmatch(r"\d{8}T\d{6}Z", value):
            stamps[prop] = f"{value[0:4]}-{value[4:6]}-{value[6:8]}T{value[9:11]}:{value[11:13]}:{value[13:15]}Z"
        elif prop == "CONTACT":
            # Annex A.4, revision 2: the address a mailto: ALTREP names, else
            # the text, lowercased (A.6); the text decoded as the name, none
            # when the address was read from a text that is an addr-spec.
            text = re.sub(r"\\([\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)
            altrep = [p.split("=", 1)[1].strip('"') for p in params if p.upper().startswith("ALTREP=")]
            if altrep and altrep[0].lower().startswith("mailto:"):
                contacts.append((altrep[0][7:].lower(), text or None))
            elif text:
                addr_spec = re.fullmatch(r"[^\s@<>]+@[^\s@<>]+", text) is not None
                contacts.append((text.lower(), None if addr_spec else text))
        elif prop == "PRIORITY" and priority is None:
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
    created = stamps.get("CREATED", stamps.get("DTSTAMP"))
    return {"priority": priority, "categories": categories, "parent": parent, "mid": mid,
            "created": created, "contacts": contacts}


def split_property(line):
    """A content line's name and parameters from its value, on the first
    colon outside a quoted parameter value (RFC 5545 section 3.1)."""
    quoted = False
    for index, char in enumerate(line):
        if char == '"':
            quoted = not quoted
        elif char == ":" and not quoted:
            return line[:index], line[index + 1:]
    return line, ""


# A message's header as STORAGE.md Annex A.1 reads it, by a second path written
# from the prose: nothing of the email package, whose parsers are lenient where
# the annex is exact. Whitespace is the space and the tab.
WSP = " \t"


def header_fields(bytes_):
    """The header block's fields as (lowercased name, value bytes), in order:
    the block ends at the first empty line, a line ending at CRLF, a bare LF
    or the end of the message, one CR just before the end being the line
    break's and any other CR the line's content, and a line break before a
    space or a tab is removed, the whitespace kept."""
    if bytes_.endswith(b"\r"):
        bytes_ += b"\n"
    block = re.split(rb"\r?\n\r?\n", bytes_, maxsplit=1)[0]
    unfolded = re.sub(rb"\r?\n(?=[ \t])", b"", block)
    fields = []
    for line in re.split(rb"\r?\n", unfolded):
        name, colon, value = line.partition(b":")
        if colon:
            fields.append((name.strip().decode("ascii", "replace").lower(), value))
    return fields


def header_field(fields, name):
    """A field's first occurrence, its bytes read as UTF-8, each maximal
    subpart of an ill-formed sequence one U+FFFD (Annex A.0), which is what
    the codec's replace handler does."""
    for header, value in fields:
        if header == name:
            return value.decode("utf-8", "replace")
    return None


def structure(text):
    """Walks a structured value: (index, char, depth, quoted, escaped) per
    character, depth the comment nesting, quoted inside a quoted-string, a
    backslash quoting the next character in either (RFC 5322 section 3.2)."""
    depth, quoted, escaped = 0, False, False
    for at, char in enumerate(text):
        if escaped:
            escaped = False
            yield at, char, depth, quoted, True
        elif char == "\\" and (depth or quoted):
            escaped = True
            yield at, char, depth, quoted, False
        elif not quoted and char == "(":
            depth += 1
            yield at, char, depth, quoted, False
        elif not quoted and char == ")" and depth:
            yield at, char, depth, quoted, False
            depth -= 1
        elif not depth and char == '"':
            quoted = not quoted
            yield at, char, depth, True, False
        else:
            yield at, char, depth, quoted, False


def uncommented(text):
    """The text with each comment read as one space."""
    out = []
    for at, char, depth, quoted, escaped in structure(text):
        if not depth:
            out.append(char)
        elif char == "(" and depth == 1 and not escaped:
            out.append(" ")
    return "".join(out)


# The labels of the WHATWG Encoding Standard this second path decodes; one it
# names with no decoder here fails the run rather than reading as unknown.
UTF8_LABELS = {"unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8", "utf-8", "utf8", "x-unicode20utf8"}
WINDOWS_1252_LABELS = {
    "ansi_x3.4-1968", "ascii", "cp1252", "cp819", "csisolatin1", "ibm819", "iso-8859-1", "iso-ir-100",
    "iso8859-1", "iso88591", "iso_8859-1", "iso_8859-1:1987", "l1", "latin1", "us-ascii", "windows-1252",
    "x-cp1252",
}
REPLACEMENT_LABELS = {"csiso2022kr", "hz-gb-2312", "iso-2022-cn", "iso-2022-cn-ext", "iso-2022-kr", "replacement"}


def charset_text(label, octets):
    """Octets in a charset the WHATWG Encoding Standard labels, or None for a
    charset it does not, or labels as its replacement encoding."""
    label = label.split("*", 1)[0].lower()
    if label in UTF8_LABELS:
        return octets.decode("utf-8", "replace")
    if label in WINDOWS_1252_LABELS:
        # The five bytes cp1252 leaves undefined are the C1 controls of the
        # same value in the WHATWG index.
        return "".join(chr(b) if b in (0x81, 0x8D, 0x8F, 0x90, 0x9D) else bytes([b]).decode("cp1252") for b in octets)
    if label in REPLACEMENT_LABELS:
        return None
    try:
        codecs.lookup(label)
    except LookupError:
        return None
    failures.append(f"charset {label}: a label checks/vectors.py does not decode")
    return None


def b_octets(text):
    """Base64 (RFC 4648 section 4), its trailing padding optional, or None."""
    bare = text.rstrip("=")
    if len(text) - len(bare) > 2 or not re.fullmatch(r"[A-Za-z0-9+/]*", bare) or len(bare) % 4 == 1:
        return None
    return base64.b64decode(bare + "=" * (-len(bare) % 4))


def q_octets(text):
    """RFC 2047 section 4.2's Q, or None on an `=` not followed by two
    hexadecimal digits."""
    out, at = bytearray(), 0
    while at < len(text):
        if text[at] == "_":
            out.append(0x20)
            at += 1
        elif text[at] == "=":
            pair = text[at + 1:at + 3]
            if not re.fullmatch(r"[0-9A-Fa-f]{2}", pair):
                return None
            out.append(int(pair, 16))
            at += 3
        else:
            out.append(ord(text[at]))
            at += 1
    return bytes(out)


# An encoded word (RFC 2047 section 2): a charset token, B or Q, and one or
# more printable ASCII characters other than `?`, a space being none.
ENCODED_WORD = re.compile(r'=\?([^\x00-\x20()<>@,;:\\"/\[\]?.=\x7f]+)\?([BbQq])\?([\x21-\x3e\x40-\x7e]+)\?=')


def unstructured(text):
    """An unstructured value (Annex A.1): every encoded word decoded wherever
    it stands, a malformed one or one in an unknown charset kept as written,
    the whitespace between two decoded words removed, the ends trimmed."""
    pieces, at = [], 0
    for match in ENCODED_WORD.finditer(text):
        pieces.append(("text", text[at:match.start()]))
        octets = (b_octets if match.group(2) in "Bb" else q_octets)(match.group(3))
        decoded = None if octets is None else charset_text(match.group(1), octets)
        pieces.append(("text", match.group(0)) if decoded is None else ("word", decoded))
        at = match.end()
    pieces.append(("text", text[at:]))
    kept = [
        value for index, (kind, value) in enumerate(pieces)
        if not (kind == "text" and 0 < index < len(pieces) - 1 and value.strip(WSP) == ""
                and pieces[index - 1][0] == pieces[index + 1][0] == "word")
    ]
    return "".join(kept).strip(WSP)


def message_ids(text, first):
    """The msg-ids of a Message-ID (the first alone) or an In-Reply-To field
    (Annex A.1): each `<` outside a comment to the next `>`, trimmed, empty
    ones dropped; a field with no such `<` read bracketless, a word of it,
    comments read as spaces, an id when it holds one `@` and no angle bracket
    or double quote, the whole field one such word for a Message-ID."""
    found, opened = [], None
    for at, char, depth, quoted, escaped in structure(text):
        if opened is not None:
            if char == ">":
                found.append(text[opened:at].strip(WSP))
                opened = None
                if first:
                    break
        elif not depth and char == "<":
            opened = at + 1
    if found or opened is not None:
        return [id_ for id_ in found if id_][:1 if first else None]
    words = [word for word in re.split(r"[ \t]+", uncommented(text)) if word]
    if first and len(words) != 1:
        return []
    return [word for word in words if word.count("@") == 1 and not set(word) & set('<>"')]


MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
ZONES = {"ut": 0, "gmt": 0, "edt": -240, "est": -300, "cdt": -300, "cst": -360, "mdt": -360,
         "mst": -420, "pdt": -420, "pst": -480}


def mail_date(text):
    """RFC 5322's date-time with section 4.3's obsolete forms, as Annex A.1
    reads it, an RFC 3339 instant in UTC, or None when unparseable."""
    text = uncommented(text)
    if "," in text:
        text = text.split(",", 1)[1]
    words = [word for word in re.split(r"[ \t]+", re.sub(r"[ \t]*:[ \t]*", ":", text)) if word]
    if len(words) != 5:
        return None
    day, month, year, clock, zone = words
    clock = re.fullmatch(r"(\d\d):(\d\d)(?::(\d\d))?", clock)
    if not re.fullmatch(r"\d{1,2}", day) or month.lower() not in MONTHS or not re.fullmatch(r"\d{2,}", year) or not clock:
        return None
    full = int(year) + {2: 2000 if int(year) < 50 else 1900, 3: 1900}.get(len(year), 0)
    if not 1900 <= full <= 9999:
        return None
    number = MONTHS.index(month.lower()) + 1
    hour, minute, second = int(clock.group(1)), int(clock.group(2)), int(clock.group(3) or 0)
    if not (1 <= int(day) <= monthrange(full, number)[1] and hour <= 23 and minute <= 59 and second <= 60):
        return None
    numeric = re.fullmatch(r"([+-])(\d\d)([0-5]\d)", zone)
    if numeric:
        offset = (int(numeric.group(2)) * 60 + int(numeric.group(3))) * (-1 if numeric.group(1) == "-" else 1)
    elif zone.lower() in ZONES:
        offset = ZONES[zone.lower()]
    elif re.fullmatch(r"[A-IK-Za-ik-z]", zone):
        offset = 0
    else:
        return None
    stated = datetime(full, number, int(day), hour, minute, min(second, 59))
    try:
        instant = stated - timedelta(minutes=offset)
    except OverflowError:
        return None
    return None if instant.year > 9999 else instant.strftime("%Y-%m-%dT%H:%M:%SZ")


def display_name(phrase):
    """The text before a mailbox's `<` (Annex A.1): comments read as spaces,
    each quoted-string its content with its quoted pairs undone, decoded as
    an unstructured value; None when empty."""
    out = []
    for at, char, depth, quoted, escaped in structure(phrase):
        if depth:
            if char == "(" and depth == 1 and not escaped:
                out.append(" ")
        elif escaped or not (char == '"' or (char == "\\" and quoted)):
            out.append(char)
    return unstructured("".join(out)) or None


def mailboxes(text):
    """An address list's (canonical address, name) pairs in document order:
    split at the commas outside quoted-strings, comments and angle brackets,
    a group's name, colon and closing `;` dropped (Annex A.1, A.6)."""
    segments, current, angled = [], [], False
    for at, char, depth, quoted, escaped in structure(text):
        if not (depth or quoted or escaped):
            if char in "<>":
                angled = char == "<"
            elif not angled and char == ":" and "@" not in "".join(current):
                current = []
                continue
            elif not angled and char in ",;":
                segments.append("".join(current))
                current = []
                continue
        current.append(char)
    segments.append("".join(current))
    found = []
    for segment in segments:
        opened = next((at for at, char, depth, quoted, escaped in structure(segment)
                       if char == "<" and not (depth or quoted)), None)
        if opened is not None and ">" in segment[opened:]:
            address = segment[opened + 1:segment.index(">", opened)].strip(WSP)
            name = display_name(segment[:opened])
        else:
            address, name = uncommented(segment).strip(WSP), None
        if address:
            found.append((address.lower(), name))
    return found


def mail_columns(bytes_):
    """The columns of mail_summary Annex A.1 reads from a header field."""
    fields = header_fields(bytes_)
    message_id = header_field(fields, "message-id")
    in_reply_to = header_field(fields, "in-reply-to")
    subject = header_field(fields, "subject")
    date_ = header_field(fields, "date")
    sender = mailboxes(header_field(fields, "from") or "")
    return {
        "message_id": (message_ids(message_id, True) or [None])[0] if message_id is not None else None,
        "in_reply_to": message_ids(in_reply_to, False) if in_reply_to is not None else [],
        "subject": unstructured(subject) if subject is not None else "",
        "sender": sender[0][0] if sender else None,
        "sender_name": sender[0][1] if sender else None,
        "date": mail_date(date_) if date_ is not None else None,
    }


# A calendar time as STORAGE.md Annex A.3 resolves it: the resource's own
# VTIMEZONE, then the IANA time zone database, then floating, an ambiguous or
# a skipped wall time at the offset in effect before the transition (RFC 5545
# section 3.3.5).
WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def components(bytes_):
    """A resource's components as (name, properties, children), a property
    (NAME, {PARAMETER: value}, value), its lines unfolded."""
    text = bytes_.decode("utf-8", "replace").replace("\r\n ", "").replace("\r\n\t", "")
    root = ("", [], [])
    stack = [root]
    for line in filter(None, text.split("\r\n")):
        head, value = split_property(line)
        name, *params = head.split(";")
        if name.upper() == "BEGIN":
            stack[-1][2].append((value.upper(), [], []))
            stack.append(stack[-1][2][-1])
        elif name.upper() == "END":
            stack.pop()
        else:
            parameters = {p.partition("=")[0].upper(): p.partition("=")[2].strip('"') for p in params}
            stack[-1][1].append((name.upper(), parameters, value))
    return root


def calendar_property(component, name):
    return next(((params, value) for prop, params, value in component[1] if prop == name), None)


def zone_offset(value):
    """A UTC offset (RFC 5545 section 3.3.14) in minutes."""
    minutes = int(value[1:3]) * 60 + int(value[3:5])
    return -minutes if value[0] == "-" else minutes


# A rule stepping by a fixed span, and the bound on the periods an observance's
# rule is followed for (STORAGE.md Annex A.3), read from the prose so a number
# the prose moves moves here.
STEPS = {"SECONDLY": 1, "MINUTELY": 60, "HOURLY": 3600, "DAILY": 86400}
ZONE_BOUND = re.search(r"observance's `RRULE` is followed for at most ([\d,]+) periods",
                       (Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "STORAGE.md").read_text())
ZONE_PERIODS = int(ZONE_BOUND.group(1).replace(",", "")) if ZONE_BOUND else 10 ** 18
require("STORAGE.md Annex A.3 bounds the periods a VTIMEZONE rule is followed for", ZONE_BOUND is not None)


def onsets(observance, years):
    """The local onsets of a STANDARD or DAYLIGHT observance over some years,
    from its DTSTART and a yearly RRULE by month and nth weekday, or a rule
    stepping by a fixed span, which yields the onsets of its first periods
    within the years and the last one before them; another shape fails the
    run."""
    start = datetime.strptime(calendar_property(observance, "DTSTART")[1], "%Y%m%dT%H%M%S")
    rule = calendar_property(observance, "RRULE")
    if rule is None:
        return [start]
    parts = dict(part.split("=", 1) for part in rule[1].split(";"))
    if parts.get("FREQ") in STEPS and set(parts) <= {"FREQ", "INTERVAL"}:
        step = STEPS[parts["FREQ"]] * int(parts.get("INTERVAL", "1"))
        since = int((datetime(years[0], 1, 1) - start).total_seconds())
        until = int((datetime(years[-1] + 1, 1, 1) - start).total_seconds())
        first = max(0, -(-since // step))
        last = min(ZONE_PERIODS, until // step + 1)
        if last - first > 10000:
            failures.append(f"VTIMEZONE rule {rule[1]}: more onsets than checks/vectors.py expands")
            return []
        before = [min(first, ZONE_PERIODS) - 1] if min(first, ZONE_PERIODS) > 0 else []
        return [start + timedelta(seconds=step * k) for k in before + list(range(first, last))]
    byday = re.fullmatch(r"([+-]?\d)(MO|TU|WE|TH|FR|SA|SU)", parts.get("BYDAY", ""))
    if parts.get("FREQ") != "YEARLY" or set(parts) != {"FREQ", "BYMONTH", "BYDAY"} or not byday:
        failures.append(f"VTIMEZONE rule {rule[1]}: a shape checks/vectors.py does not expand")
        return []
    found = []
    for year in years:
        days = [date(year, int(parts["BYMONTH"]), d) for d in range(1, monthrange(year, int(parts["BYMONTH"]))[1] + 1)]
        days = [d for d in days if d.weekday() == WEEKDAYS.index(byday.group(2))]
        day = days[int(byday.group(1)) - 1 if int(byday.group(1)) > 0 else int(byday.group(1))]
        if year >= start.year:
            found.append(datetime.combine(day, start.time()))
    return found


def through_vtimezone(vtimezone, wall):
    """A wall time as UTC through a VTIMEZONE, an ambiguous or a skipped one
    at the offset in effect before its transition."""
    transitions = sorted(
        (onset - timedelta(minutes=zone_offset(calendar_property(o, "TZOFFSETFROM")[1])),
         zone_offset(calendar_property(o, "TZOFFSETFROM")[1]), zone_offset(calendar_property(o, "TZOFFSETTO")[1]))
        for o in vtimezone[2] if o[0] in ("STANDARD", "DAYLIGHT")
        for onset in onsets(o, range(wall.year - 1, wall.year + 2)))
    for utc, before, after in transitions:
        earlier, later = sorted((utc + timedelta(minutes=before), utc + timedelta(minutes=after)))
        if earlier <= wall < later:
            return wall - timedelta(minutes=before)

    def in_effect(instant):
        return ([after for utc, before, after in transitions if utc <= instant] or [transitions[0][1]])[-1]

    offsets = {offset for transition in transitions for offset in transition[1:]}
    return next(wall - timedelta(minutes=o) for o in offsets if in_effect(wall - timedelta(minutes=o)) == o)


def calendar_instant(params, value, vtimezones):
    """A DATE-TIME or a DATE as Annex A.3's instant, or None."""
    if params.get("VALUE", "").upper() == "DATE" or re.fullmatch(r"\d{8}", value):
        return f"{value[0:4]}-{value[4:6]}-{value[6:8]}T00:00:00Z" if re.fullmatch(r"\d{8}", value) else None
    stamp = re.fullmatch(r"(\d{8}T\d{6})(Z?)", value)
    if stamp is None:
        return None
    wall = datetime.strptime(stamp.group(1), "%Y%m%dT%H%M%S")
    tzid = params.get("TZID")
    if not stamp.group(2) and tzid is not None:
        if tzid in vtimezones:
            wall = through_vtimezone(vtimezones[tzid], wall)
        else:
            try:
                wall = wall.replace(tzinfo=ZoneInfo(tzid), fold=0).astimezone(timezone.utc).replace(tzinfo=None)
            except (ZoneInfoNotFoundError, ValueError):
                pass
    return wall.strftime("%Y-%m-%dT%H:%M:%SZ")


def calendar_sort_key(bytes_):
    """Annex A.3 to A.5's sort key: the master's DTSTART, a task's DUE before
    it, as an instant, '' when none reads as one."""
    calendar_ = components(bytes_)[2][0]
    vtimezones = {calendar_property(c, "TZID")[1]: c for c in calendar_[2] if c[0] == "VTIMEZONE"}
    master = next((c for c in calendar_[2] if c[0] in ("VEVENT", "VTODO", "VJOURNAL")
                   and calendar_property(c, "RECURRENCE-ID") is None), None)
    if master is None:
        return ""
    for name in ("DUE", "DTSTART") if master[0] == "VTODO" else ("DTSTART",):
        found = calendar_property(master, name)
        instant = found and calendar_instant(found[0], found[1], vtimezones)
        if instant:
            return instant
    return ""


def text_value(value):
    """A vCard or iCalendar text value unescaped (RFC 6350 section 3.4, RFC
    5545 section 3.3.11): a backslash before a comma, a semicolon or itself
    is dropped, and one before n or N is a line break."""
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def card_rows(bytes_):
    """Annex A.2's columns, address rows and sort key of a card, by a second
    path: the lines unfolded and split by hand, a property's group prefix
    dropped, nothing but the stdlib."""
    text = bytes_.decode("utf-8", "replace").replace("\r\n ", "").replace("\r\n\t", "")
    props = []
    for line in filter(None, text.split("\r\n")):
        head, value = split_property(line)
        props.append((head.split(";")[0].split(".")[-1].upper(), value))

    def first(name):
        return next((value for prop, value in props if prop == name), None)

    fn, kind, org = first("FN"), first("KIND"), first("ORG")
    columns = {
        "uid": first("UID"),
        "fn": text_value(fn) if fn is not None else "",
        "kind": kind.lower() if kind is not None else None,
        "org": text_value(re.split(r"(?<!\\);", org)[0]) if org is not None else None,
    }
    addresses = [("email", position, value.lower(), None)
                 for position, value in enumerate(value for prop, value in props if prop == "EMAIL")]
    return columns, addresses, columns["fn"].lower().strip()


def calendar_rows(bytes_):
    """Annex A.3 to A.5's columns read from the master component verbatim or
    decoded, and its ORGANIZER and ATTENDEE rows (A.3, A.6), by the reader
    above; the task columns task_columns() derives are left to it."""
    calendar_ = components(bytes_)[2][0]
    master = next(c for c in calendar_[2] if c[0] in ("VEVENT", "VTODO", "VJOURNAL")
                  and calendar_property(c, "RECURRENCE-ID") is None)

    def value(name):
        found = calendar_property(master, name)
        return found[1] if found else None

    def text(name):
        found = value(name)
        return text_value(found) if found is not None else None

    def time(name):
        found = calendar_property(master, name)
        if found is None:
            return None, None, None
        params, stamp = found
        date_only = params.get("VALUE", "").upper() == "DATE" or re.fullmatch(r"\d{8}", stamp) is not None
        return stamp, params.get("TZID"), "date" if date_only else "date-time"

    rule = value("RRULE")
    parts = dict(part.split("=", 1) for part in rule.split(";")) if rule else {}
    columns = {"uid": value("UID"), "summary": text("SUMMARY") or ""}
    columns["dtstart"], columns["dtstart_tzid"], columns["dtstart_value"] = time("DTSTART")
    if master[0] != "VJOURNAL":
        columns["recurring"] = int(rule is not None or value("RDATE") is not None)
        columns["until"] = parts.get("UNTIL")
    if master[0] == "VEVENT":
        columns["location"] = text("LOCATION")
        columns["dtend"] = value("DTEND")
    if master[0] == "VTODO":
        columns["due"], columns["due_tzid"], columns["due_value"] = time("DUE")
        status, percent = value("STATUS"), value("PERCENT-COMPLETE")
        columns["status"] = status.upper() if status is not None else None
        columns["completed"] = value("COMPLETED")
        columns["percent"] = int(percent) if percent is not None and percent.isdigit() else None
    addresses = []
    for role, name in (("organizer", "ORGANIZER"), ("attendee", "ATTENDEE")):
        found = [(params, address) for prop, params, address in master[1] if prop == name]
        for position, (params, address) in enumerate(found):
            bare = address[7:] if address.lower().startswith("mailto:") else address
            addresses.append((role, position, bare.lower(), params.get("CN")))
    return columns, addresses


def text_of(parts):
    return "".join(part if isinstance(part, str) else part["repeat"] * part["times"] for part in parts).encode()



# The walk of a message's parts (STORAGE Annex A.1): its entities in document
# order, a multipart before its children, the message's own at depth 0, none
# deeper than 64 nor after the 10,000th read; and the stand-ins, at most the
# first 1,000 parts carrying the disposition (STORAGE section 14.3).
#
# NOTE: the stdlib parser ends a line at every lone CR, where the annex ends
# one only at a CR just before the end of the message, a lone CR elsewhere
# being content. The two agree on every fixture: none holds a lone CR the
# walk reads but mail-cut-delimiter.eml's last, and mail-stray-cr.eml's sits
# before header fields the walk does not read, its columns read above.
WALK_DEPTH, WALK_ENTITIES, STAND_INS = 64, 10_000, 1_000


def media_type(part):
    """The media type the mark reads (Annex A.1): the Content-Type value up
    to its first ;, trimmed and lowercased, text/plain when the field is
    absent, under a multipart/digest too, or when the value holds not
    exactly one /. The stdlib's own reading defaults a digest's children to
    message/rfc822, so it is not used."""
    value = part.get("Content-Type")
    stated = str(value).split(";")[0].strip().lower() if value is not None else ""
    return stated if stated.count("/") == 1 else "text/plain"


def makes_the_mark(part, protocol):
    """Whether one entity makes the attachment mark (Annex A.1): disposed as
    an attachment, any type but inline, or stating no disposition, neither
    multipart nor text and named by no Content-ID; never an RFC 1847
    protocol part."""
    if protocol:
        return False
    value = part.get("Content-Disposition")
    disposition = str(value).split(";")[0].strip().lower() if value is not None else ""
    if disposition:
        return disposition != "inline"
    kind = media_type(part).split("/")[0]
    return kind not in ("multipart", "text") and part.get("Content-ID") is None


def marked(message):
    """The parts the walk reads that make the attachment mark, by IMAP
    section (RFC 3501 section 6.4.5): the message itself 1 when it is no
    multipart, a multipart's children numbered under it, a message/rfc822
    part one entity, never opened. A multipart message's own entity, every
    child of a multipart/encrypted and every child but the first of a
    multipart/signed never make it."""
    read, found = 0, []

    def visit(part, section, depth, protocol):
        nonlocal read
        if depth > WALK_DEPTH or read >= WALK_ENTITIES:
            return
        read += 1
        multipart = part.get_content_maintype() == "multipart"
        if makes_the_mark(part, protocol) and not (multipart and depth == 0):
            found.append((part, section or "1"))
        if multipart:
            subtype = media_type(part)
            for at, child in enumerate(part.get_payload(), 1):
                child_protocol = subtype == "multipart/encrypted" or (subtype == "multipart/signed" and at > 1)
                visit(child, f"{section}.{at}" if section else str(at), depth + 1, child_protocol)

    visit(message, "", 0, False)
    return found


def attachments(message):
    """The parts a message's stand-ins name, the first STAND_INS the walk
    marks. The name is the filename, else the Content-Type name, RFC 2231
    and RFC 2047 decoded; the media type NULL when no Content-Type is
    stated; the size the transfer-decoded octets."""

    def stated(part, section):
        name = part.get_filename() or ""
        if "=?" in name:
            name = str(make_header(decode_header(name)))
        media_type = part.get_content_type() if part.get("Content-Type") is not None else None
        if part.get_content_maintype() == "multipart":
            size = None
        elif part.get_content_type() == "message/rfc822":
            # NOTE: the stdlib parses a message/rfc822 part into a message of
            # its own and keeps no octets. Such a body takes no transfer
            # encoding (RFC 2046 section 5.2.1), and serializing the parsed
            # message unfolded with CRLF gives back the octets of every
            # fixture holding one.
            out = io.BytesIO()
            BytesGenerator(out, mangle_from_=False, maxheaderlen=0).flatten(part.get_payload()[0], linesep="\r\n")
            size = len(out.getvalue())
        else:
            size = len(part.get_payload(decode=True))
        return {"part": section, "name": name, "media_type": media_type, "size": size}

    return [stated(part, section) for part, section in marked(message)[:STAND_INS]]


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "vectors"


def manifest_of(top):
    """The manifest of a tree (vectors/README.md): the SHA-256 of every file
    a vendor copies, everything under vectors/ and payloads/ but
    vectors/README.md and the manifest itself; the length of every list a
    file other than a sync case holds at its top or one level down, by JSON
    pointer; and the number of sync cases."""
    files, cases = {}, {}
    for base in ("vectors", "payloads"):
        for path in sorted((top / base).rglob("*")):
            relative = path.relative_to(top).as_posix()
            if path.is_file() and relative not in ("vectors/README.md", "vectors/manifest.json"):
                files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    for relative in files:
        if relative.endswith(".json") and relative.startswith("vectors/") and not relative.startswith(("vectors/schema/", "vectors/sync/")):
            document = json.loads((top / relative).read_text())
            lists = {f"/{key}": len(value) for key, value in document.items() if isinstance(value, list)}
            lists |= {f"/{key}/{inner}": len(value) for key, sub in document.items() if isinstance(sub, dict)
                      for inner, value in sub.items() if isinstance(value, list)}
            cases[relative] = dict(sorted(lists.items()))
    sync = sum(relative.startswith("vectors/sync/") for relative in files)
    return {"v": 1, "files": dict(sorted(files.items())), "cases": cases, "sync": sync}


# `--manifest` prints the tree's manifest, which vectors/manifest.json then
# records, and checks nothing.
if sys.argv[2:] == ["--manifest"]:
    print(json.dumps(manifest_of(root.parent), indent=2, ensure_ascii=False))
    sys.exit(0)

objects = json.loads((root / "objects.json").read_text())
summaries = json.loads((root / "summaries.json").read_text())

# Every file a vendor copies is the manifest's, byte for byte, and every case
# file holds the cases the manifest counts, so a vector deleted, altered or
# added without the manifest restating it fails here, and a vendor checking
# its copy against the manifest finds what moved. The sync cases are numbered
# from 1 with no gap and no number twice.
recorded = json.loads((root / "manifest.json").read_text()) if (root / "manifest.json").is_file() else {}
computed = manifest_of(root.parent)
for path in sorted(set(recorded.get("files", {})) | set(computed["files"])):
    if path not in recorded.get("files", {}):
        failures.append(f"{path}: in the tree, not in vectors/manifest.json")
    elif path not in computed["files"]:
        failures.append(f"{path}: in vectors/manifest.json, not in the tree")
    elif recorded["files"][path] != computed["files"][path]:
        failures.append(f"{path}: its SHA-256 is not the one vectors/manifest.json records")
check("vectors/manifest.json: the cases of each case file", recorded.get("cases"), computed["cases"])
check("vectors/manifest.json: the sync cases", recorded.get("sync"), computed["sync"])
numbers = sorted(int(path.name.split("-", 1)[0]) for path in (root / "sync").glob("*.json"))
check("vectors/sync/: numbered from 1, no gap, no number twice", numbers, list(range(1, len(numbers) + 1)))

# Every vector file carries its format's version `v` and conforms to the JSON
# Schema of its format under vectors/schema/, so a consumer reading a file of
# another version, or a field the format does not name, fails here first.
FORMATS = {
    "objects.json": "objects", "summaries.json": "summaries", "search/store.json": "search-store",
    "search/queries.json": "search-queries", "search/chunks.json": "search-chunks",
    "payloads.json": "payloads", "manifest.json": "manifest",
}
for path in sorted(root.rglob("*.json")):
    relative = path.relative_to(root).as_posix()
    if relative.startswith("schema/"):
        continue
    format_ = "sync" if relative.startswith("sync/") else FORMATS.get(relative)
    if format_ is None:
        failures.append(f"{relative}: a vector file of no known format")
        continue
    document = json.loads(path.read_text())
    require(f"{relative}: states its format's version v", isinstance(document, dict) and isinstance(document.get("v"), int))
    schema = json.loads((root / "schema" / f"{format_}.schema.json").read_text())
    for error in Draft202012Validator(schema).iter_errors(document):
        failures.append(f"{relative}: {error.json_path}: {error.message}")

# A summary row in any format names the columns of its table in the canonical
# schema (STORAGE.md section 4.3), read off migrations/storage/, a list column
# standing for its child table (mail_in_reply_to as in_reply_to, task_category
# as categories), so a column misspelt or dropped in a format's $defs, or in
# the columns read below, fails here.
store_schema = sqlite3.connect(":memory:")
for migration in sorted((root.parent / "migrations" / "storage").glob("*.sql")):
    store_schema.executescript(migration.read_text())
SQL_TABLES = {table: {row[0] for row in store_schema.execute("SELECT name FROM pragma_table_info(?)", (table,))} - {"collection", "link_id"}
              for table in (*TABLES, "file_summary")}
SQL_TABLES["mail_summary"] |= {"in_reply_to"}
SQL_TABLES["task_summary"] |= {"categories"}
check("the summary columns checks/vectors.py reads", TABLES, {table: SQL_TABLES[table] for table in TABLES})
check("the file summary columns checks/vectors.py reads", FILE_SUMMARY, SQL_TABLES["file_summary"])
for path in sorted((root / "schema").glob("*.schema.json")):
    for defined, definition in json.loads(path.read_text()).get("$defs", {}).items():
        if defined in SQL_TABLES:
            check(f"schema/{path.name} $defs/{defined}: the table's columns", set(definition["properties"]), SQL_TABLES[defined])

# The queue's payloads (STORAGE.md section 15.3, Annex B.2). Each schema under
# payloads/ is one action's at one version, and the prose writes its shape
# once: the same members, optional where the schema requires none, typed as
# the shape's placeholder says, two members joined in `( a | b )` the schema's
# one of two. Every case of payloads.json validates against its action's
# schema exactly when it says it does, so a schema loosened or a malformed
# payload fails here.
NONEMPTY = {"type": "string", "minLength": 1}
PLACEHOLDERS = {
    "n": {"type": "integer", "minimum": 1},
    "hash": {"type": "string", "pattern": "^[a-z2-7]{52}$"},
    "key": NONEMPTY, "id": NONEMPTY, "collection": NONEMPTY, "addr": NONEMPTY, "label": NONEMPTY,
    "text": {"type": "string"},
    "capability": {"type": "string", "pattern": "^[a-z][a-z0-9-]*(\\.[a-z0-9-]+)*$"},
    "[…]": {"type": "array", "uniqueItems": True, "items": {"type": "string", "pattern": "^[!-~]+$"}},
    "[addr…]": {"type": "array", "minItems": 1, "items": NONEMPTY},
    "[hash…]": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "pattern": "^[a-z2-7]{52}$"}},
}


def shape(text):
    """A payload shape as a schema: its members, those `?` marks optional and
    those a `( a | b )` joins one of two."""
    tokens = re.findall(r'"[^"]*"|\[[^\]]*\]|[{}(),:?|]|[^\s{}(),:?|"]+', text)
    at = 0

    def take(expected=None):
        nonlocal at
        token = tokens[at]
        if expected is not None and token != expected:
            raise ValueError(f"{expected} expected at {token!r}")
        at += 1
        return token

    def value():
        if tokens[at] == "{":
            return members()
        if tokens[at].startswith('"'):
            choices = [json.loads(take())]
            while tokens[at] == "|" and tokens[at + 1].startswith('"'):
                take("|")
                choices.append(json.loads(take()))
            return {"enum": choices} if len(choices) > 1 else {"const": choices[0]}
        token = take()
        if token.isdigit():
            return {"const": int(token)}
        if token not in PLACEHOLDERS:
            raise ValueError(f"no placeholder {token!r}")
        return PLACEHOLDERS[token]

    def member(properties, required):
        key = json.loads(take())
        take(":")
        properties[key] = value()
        if tokens[at] == "?":
            take("?")
        else:
            required.append(key)
        return key

    def members():
        take("{")
        properties, required, one_of = {}, [], []
        while True:
            if tokens[at] == "(":
                take("(")
                pair = []
                for index in range(2):
                    pair.append(member(properties, []))
                    take("|" if index == 0 else ")")
                one_of.append(pair)
            else:
                member(properties, required)
            if take() == "}":
                break
        result = {"type": "object", "required": sorted(required), "additionalProperties": False, "properties": properties}
        if one_of:
            result["oneOf"] = [{"required": [key]} for pair in one_of for key in pair]
        return result

    return members()


def schema_shape(schema):
    """A schema as shape() reads one, its own keywords dropped."""
    if schema.get("type") != "object":
        return schema
    result = {"type": "object", "required": sorted(schema.get("required", [])),
              "additionalProperties": schema.get("additionalProperties", True)}
    result["properties"] = {key: schema_shape(fragment) for key, fragment in schema.get("properties", {}).items()}
    if "oneOf" in schema:
        result["oneOf"] = schema["oneOf"]
    return result


payload_schemas = {path.name.removesuffix(".schema.json"): json.loads(path.read_text())
                   for path in sorted((root.parent / "payloads").glob("*.schema.json"))}
shapes = {}
for document in ("STORAGE.md", "SYNC.md", "SEARCH.md", "GUIDE.md", "OVERVIEW.md"):
    for number, line in enumerate((root.parent / document).read_text().splitlines(), 1):
        for span in re.findall(r"`(\{ \"v\": [^`]*\})`", line):
            if line.startswith("| `"):
                actions = re.findall(r"^\| `([^`]+)` \|", line)
            else:
                actions = re.findall(r"\*\*`([a-z-]+)`\*\*", line.split(": `{", 1)[0]) if line.startswith("- **`") else []
            require(f"{document}:{number}: a payload shape names its action", bool(actions))
            try:
                parsed = shape(span.replace("\\|", "|"))
            except (ValueError, IndexError, json.JSONDecodeError) as error:
                failures.append(f"{document}:{number}: a payload shape that does not read: {error}")
                continue
            for action in actions:
                version = parsed["properties"]["v"].get("const")
                require(f"{document}:{number}: {action} written twice", f"{action}.v{version}" not in shapes)
                shapes[f"{action}.v{version}"] = parsed
check("the payload shapes the documents write", sorted(shapes), sorted(payload_schemas))
for action_version in sorted(set(shapes) & set(payload_schemas)):
    check(f"payloads/{action_version}.schema.json against its shape", schema_shape(payload_schemas[action_version]), shapes[action_version])
    require(f"payloads/{action_version}.schema.json: a JSON Schema", payload_schemas[action_version].get("$schema", "").endswith("2020-12/schema"))
payload_cases = json.loads((root / "payloads.json").read_text())["cases"] if (root / "payloads.json").exists() else []
require("payloads.json: the queue's payload cases", bool(payload_cases))
for index, case in enumerate(payload_cases):
    action_version = f"{case['action']}.v{case['payload'].get('v')}"
    if action_version not in payload_schemas:
        failures.append(f"payloads.json case {index}: no schema {action_version}")
        continue
    errors = [error.message for error in Draft202012Validator(payload_schemas[action_version]).iter_errors(case["payload"])]
    check(f"payloads.json case {index} ({case['action']}, {case.get('note', 'valid')}) valid", not errors, case["valid"])
for action_version in payload_schemas:
    require(f"payloads.json: a valid and a malformed {action_version}",
            {case["valid"] for case in payload_cases
             if f"{case['action']}.v{case['payload'].get('v')}" == action_version} == {True, False})


def shell_word(text):
    """A double-quoted shell word's value: a backslash quoting `$`, a
    backquote, `"` or itself, and a variable, `$h1` or `${h1}`, standing for
    a body's name, which is all checks/invariants.sh interpolates into a
    payload."""
    out, at = [], 0
    while at < len(text):
        if text[at] == "\\" and text[at + 1:at + 2] in ("$", "`", '"', "\\"):
            out.append(text[at + 1])
            at += 2
        elif text[at] == "$" and re.match(r"\{?[a-z_][a-z0-9_]*\}?", text[at + 1:]):
            out.append("a" * 52)
            at += 1 + re.match(r"\{?[a-z_][a-z0-9_]*\}?", text[at + 1:]).end()
        else:
            out.append(text[at])
            at += 1
    return "".join(out)


# The scenarios enqueue well-formed payloads (STORAGE.md section 15.3), the
# store reading none: each payload checks/invariants.sh writes is valid against
# its action's schema, but one whose call a comment opening `# A malformed
# payload` heads, which must be invalid.
harness = (root.parent / "checks" / "invariants.sh").read_text().replace("\\\n", " ")
enqueued = 0
for number, line in enumerate(harness.splitlines()):
    if "queue/enqueue_action" not in line or line.lstrip().startswith("#"):
        continue
    action = re.search(r'":action=\'([a-z-]+)\'"', line)
    payload = re.search(r'":payload=\'((?:[^"\\]|\\.)*)\'"', line)
    if action is None or payload is None:
        failures.append(f"checks/invariants.sh: an enqueue states no literal action and payload: {line.strip()[:80]}")
        continue
    above = number - 1
    while above >= 0 and harness.splitlines()[above].lstrip().startswith("#"):
        above -= 1
    malformed = harness.splitlines()[above + 1].lstrip().startswith("# A malformed payload")
    document = json.loads(shell_word(payload.group(1)))
    schema = payload_schemas.get(f"{action.group(1)}.v{document.get('v')}")
    valid = schema is not None and not list(Draft202012Validator(schema).iter_errors(document))
    check(f"checks/invariants.sh: the {action.group(1)} payload {json.dumps(document)[:60]} valid", valid, not malformed)
    enqueued += 1
require("checks/invariants.sh: enqueues payloads", enqueued > 0)

for case in objects["base32"]["cases"]:
    encoded = name(bytes.fromhex(case["input_hex"]))
    check(f"base32 of {case['input_utf8']!r}", encoded, case["base32"])

for case in objects["objects"]:
    bytes_ = body(case)
    check(f"{case['label']} length", len(bytes_), case["body_len"])

    # One shard level (STORAGE section 5): the first two characters of the
    # name, then the name, so a store holds at most 1,024 shard directories.
    digest = blake3(bytes_).digest()
    object_name = name(digest)
    check(f"{case['label']} digest", digest.hex(), case["blake3"]["digest_hex"])
    check(f"{case['label']} name", object_name, case["blake3"]["name"])
    require(f"{case['label']} name is 52 characters of base32", NAME.fullmatch(case["blake3"]["name"]) is not None)
    check(f"{case['label']} path", f"objects/{object_name[:2]}/{object_name}", case["blake3"]["path"])

fixtures = set()
# A fixture's link id where Annex A gives it alone, no key minted over it.
links_of_fixtures = {case["fixture"]: case["link_id"] for case in summaries["cases"] if "hint" not in case}

for case in summaries["cases"]:
    fixtures.add(case["fixture"])
    bytes_ = (root / case["fixture"]).read_bytes()

    if bytes_.count(b"\n") != bytes_.count(b"\r\n"):
        failures.append(f"{case['fixture']}: not CRLF throughout, so something converted it")
        continue

    check(f"{case['fixture']} length", len(bytes_), case["body"]["len"])

    check(f"{case['fixture']} blake3", name(blake3(bytes_).digest()), case["body"]["blake3"])

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
        # The mark with the body (Annex A.1): 1 when a part the walk reads
        # carries the disposition, whatever the stand-ins' bound.
        check(f"{case['label']} attachment", case["summary"]["attachment"], int(bool(marked(message_from_bytes(bytes_)))))
        # Every column read from a header field, re-derived by the second path
        # above from the parses Annex A.1 states, and the key read from the
        # date (Annex A.1, revision 3).
        derived = mail_columns(bytes_)
        check(f"{case['label']} header columns", {column: case["summary"][column] for column in derived}, derived)
        check(f"{case['label']} sort_key", case["sort_key"], derived["date"] or "")
        # Every mailbox of From, To, Cc and Bcc, canonical, with its decoded
        # display name, numbered in document order within its role (A.1, A.6).
        fields = header_fields(bytes_)
        check(f"{case['label']} address rows", sorted(
            (address["role"], address["position"], address["address"], address["name"]) for address in case["addresses"]
        ), sorted(
            (role, position, address, name) for role in ("from", "to", "cc", "bcc")
            for position, (address, name) in enumerate(mailboxes(header_field(fields, role) or ""))
        ))

    # A card's columns, its EMAIL rows and its sort key (Annex A.2).
    if case["table"] == "contact_summary":
        columns, rows, sort_key = card_rows(bytes_)
        check(f"{case['label']} card columns", case["summary"], columns)
        check(f"{case['label']} card address rows", sorted(
            (address["role"], address["position"], address["address"], address["name"]) for address in case["addresses"]
        ), rows)
        check(f"{case['label']} sort_key", case["sort_key"], sort_key)

    # A calendar item's columns and its ORGANIZER, ATTENDEE and, for a task,
    # CONTACT rows (A.3 to A.5); task_columns() below reads the rest.
    if case["table"] in ("event_summary", "task_summary", "journal_summary"):
        columns, rows = calendar_rows(bytes_)
        check(f"{case['label']} calendar columns", {column: case["summary"][column] for column in columns}, columns)
        check(f"{case['label']} calendar columns read", set(columns) | ({"priority", "categories", "parent", "mid", "created"}
              if case["table"] == "task_summary" else set()), TABLES[case["table"]])
        check(f"{case['label']} organizer and attendee rows", sorted(
            (address["role"], address["position"], address["address"], address["name"]) for address in case["addresses"]
            if address["role"] in ("organizer", "attendee")
        ), sorted(rows))

    # A calendar item's key: its master's DTSTART, a task's DUE first, as an
    # instant through the resource's VTIMEZONE, the IANA database or neither
    # (Annex A.3 to A.5).
    if case["table"] in ("event_summary", "task_summary", "journal_summary"):
        check(f"{case['label']} sort_key", case["sort_key"], calendar_sort_key(bytes_))

    for address in case["addresses"]:
        require(f"{case['label']} role {address['role']}", address["role"] in ROLES)
        check(f"{case['label']} address {address['address']} canonical", address["address"], address["address"].lower())

    if "hint" in case:
        minted = f"dup:{case['hint']}#{case['handle']}"
        check(f"{case['label']} minted link_id", minted, case["link_id"])

    if case["summary"].get("uid") is None and case["table"] != "mail_summary":
        check(f"{case['label']} hash: link_id", case["link_id"], "hash:" + fnv1a(bytes_))

    # A stated identity is the link id verbatim, escaped when it begins with a
    # prefix the writer derives keys under (STORAGE section 9), so a UID
    # stating hash: never reads as a key derived from the bytes.
    stated = case["summary"].get("message_id" if case["table"] == "mail_summary" else "uid")
    if stated is not None and "hint" not in case:
        escaped = "esc:" + stated if stated.startswith(RESERVED_PREFIXES) else stated
        check(f"{case['label']} link_id of a stated identity", case["link_id"], escaped)

    if case["table"] == "mail_summary" and case["summary"]["message_id"] is None and "hint" not in case:
        row = case["summary"]
        alt = "alt:" + "|".join(row[column] or "" for column in ("subject", "date", "sender"))
        check(f"{case['label']} alt: link_id", case["link_id"], alt)

    if case["table"] == "task_summary":
        derived = task_columns(bytes_)
        contacts = derived.pop("contacts")
        check(f"{case['label']} task columns", {
            column: case["summary"][column] for column in ("priority", "categories", "parent", "mid", "created")
        }, derived)
        check(f"{case['label']} contact addresses", [
            (address["address"], address["name"]) for address in case["addresses"] if address["role"] == "contact"
        ], contacts)
        check(f"{case['label']} contact positions", [
            address["position"] for address in case["addresses"] if address["role"] == "contact"
        ], list(range(len(contacts))))


# The sync cases (SYNC.md section 11): shape and references only.
sync_cases = sorted((root / "sync").glob("*.json"))

for path in sync_cases:
    case = json.loads(path.read_text())
    label = path.name
    for key in ("label", "store", "run", "remote", "expect"):
        require(f"{label}: has {key}", key in case)
    store = case["store"]
    # An expected store may hold a body the run fetched, which it declares.
    labels = set(store.get("objects", {})) | set(case["expect"].get("store", {}).get("objects", {}))
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
    # The closed vocabularies (STORAGE section 13): a kind of the set, the
    # ladder 1 and 2.
    for collection in declared:
        require(f"{label}: collection {collection['id']} has a kind of the set", collection["kind"] in KINDS)
    # Under a prefer- policy an item conflict is recorded only while one of its
    # two bodies is unread, the incoming one or the item's own, and reading it
    # settles it by the policy (SYNC.md sections 6 and 9), so no such conflict
    # holds both.
    policies = {c["id"]: c.get("conflict", "manual") for c in declared}
    for item in store.get("items", []) + expected.get("items", []):
        require(f"{label}: item {item['link_id']} in a known collection", item["collection"] in collections)
        for column in ("object", "conflict_object"):
            require(f"{label}: item {item['link_id']} {column} names a known object", item.get(column) in labels | {None})
        if policies.get(item["collection"], "manual") != "manual" and item.get("conflicted") == 1:
            require(f"{label}: item {item['link_id']} under {policies[item['collection']]}, an item conflict waits for one body to be read", item.get("conflict_object") is None or item.get("object") is None)
        if "level" in item:
            require(f"{label}: item {item['link_id']} has a level of the ladder", item["level"] in (1, 2))
    # An expected reference names two ends the expected store holds (STORAGE
    # section 14.2).
    kinds = {c["id"]: c["kind"] for c in declared}
    held = {(kinds.get(item["collection"]), item["link_id"]) for item in expected.get("items", [])}
    for reference in expected.get("references", []):
        for end in ("from", "to"):
            endpoint = (reference[f"{end}_kind"], reference[f"{end}_link_id"])
            require(f"{label}: reference {end} {endpoint} is held", endpoint in held)
    for binding in store.get("bindings", []) + case["expect"].get("store", {}).get("bindings", []):
        for column in ("base_object", "conflict_object", "shared_object"):
            require(f"{label}: binding {binding['handle']} {column} names a known object", binding.get(column) in labels | {None})
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
        require(f"{label}: page {at} carries a cursor unless it is the last, or the run fails on it", page.get("last") or page.get("cursor") is not None or case["expect"].get("failed") is True)
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
    # 5): every Remove pushed names a binding of an item the store held as a
    # tombstone, the consumer's or one a delete on another source left there
    # (section 9), or the one a mutate run removes.
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

    # Which absences delete (SYNC.md section 5): a based binding of the run's
    # source leaves the store only for a removal its remote stated, an absence
    # from a round the run closed, in that round's scope and not parked, a
    # tombstone pushed, or a rekey. A round whose absences would drop more
    # than half of a scope of at least 20 bound members parks unless the run
    # accepts them.
    run, after = case["run"], case["expect"].get("store", {})
    # A member stating a Message-ID the store holds under a summary naming
    # another message (another subject, date or sender, SYNC.md section 6,
    # STORAGE.md section 9) is minted apart, never bound to the row holding
    # it, whatever that row is: a pending create, a live item others or none
    # bind, a tombstone, a retained row. A retained row agrees on the size too
    # where both state one, its body becoming the member's unread as a link's.
    held_rows = {(s["collection"], s["link_id"]): s["row"] for s in store.get("summaries", []) if s["table"] == "mail_summary"}
    retained_rows = {(item["collection"], item["link_id"]) for item in store.get("items", []) if item.get("retained") is True}
    for page in pages:
        for member in page["items"]:
            meta = member.get("meta") or {}
            if files or not (root / meta.get("body", "")).is_file() or not meta["body"].endswith(".eml"):
                continue
            body = (root / meta["body"]).read_bytes()
            columns = mail_columns(body)
            message_id = columns["message_id"]
            row = held_rows.get((run["collection"], message_id))
            if row is None:
                continue
            size = meta.get("size", len(body))
            if any(columns[column] != row.get(column, columns[column]) for column in ("subject", "date", "sender")) or (
                    (run["collection"], message_id) in retained_rows and row.get("size") is not None and size != row["size"]):
                require(f"{label}: member {member['handle']} names another message under {message_id} and is minted apart",
                        all(binding["link_id"] != message_id for binding in after.get("bindings", [])
                            if binding["handle"] == member["handle"] and binding["source"] == run["source"]))
    # A body a policy or an overruling Edit keeps (SYNC.md sections 7 and 9)
    # is a retained item keyed by the identity minted over the settling
    # binding's handle, minted again while the key is held (STORAGE.md section
    # 9): by any row of the collection before the run, a retained one
    # included, or by a body the same write kept first. So no kept body takes
    # another's key, revives it or fails on it.
    held_keys = {item["link_id"] for item in store.get("items", []) if item["collection"] == run["collection"]}
    kept = {(item["collection"], item["link_id"]): item for item in after.get("items", [])}
    for event in case["expect"].get("events", []):
        if event.get("kind") != "Overruled":
            continue
        # The settling binding: one of the store, or the one a revive binds
        # (STORAGE.md section 11.1).
        binding = next((b for b in store.get("bindings", []) + after.get("bindings", [])
                        if b["collection"] == run["collection"] and b["handle"] == event.get("handle")), None)
        require(f"{label}: Overruled {event.get('handle')} names a binding of the store or one the run binds", binding is not None)
        if binding is None:
            continue
        key = f"dup:{binding['link_id']}#{event['handle']}"
        while key in held_keys:
            key = f"dup:{key}#{event['handle']}"
        check(f"{label}: Overruled {event['handle']} key", event.get("link_id"), key)
        held_keys.add(key)
        if "items" in after:
            row = kept.get((run["collection"], key), {})
            require(f"{label}: Overruled {key} is a retained item", row.get("deleted") == 1 and row.get("retained") is True)
    # No policy and no revive leaves a body facing a server edit nobody has
    # read (SYNC.md sections 5, 6 and 9, STORAGE.md section 11.1): a binding
    # whose base names a revision and no body never faces a live, unconflicted
    # item holding one, which its next sync would push over that edit.
    after_items = {(item["collection"], item["link_id"]): item for item in after.get("items", [])}
    for binding in after.get("bindings", []):
        if kinds.get(binding["collection"]) == "message/rfc822" or binding.get("conflicted") == 1:
            continue
        if binding.get("base_present", 0) != 1 or binding.get("base_revision") is None or binding.get("base_object") is not None:
            continue
        item = after_items.get((binding["collection"], binding["link_id"]), {})
        if item.get("deleted") == 1 or item.get("conflicted") == 1:
            continue
        require(f"{label}: binding {binding['handle']}, its server's body unread, faces no body it would push over it", item.get("object") is None)
    # No collection policy chooses against a body nobody read (SYNC.md section
    # 9): a prefer- settle reported Overruled leaves the item holding a body,
    # never the absence of one it would otherwise have kept as the winner.
    if policies.get(run["collection"], "manual") != "manual":
        for event in case["expect"].get("events", []):
            if event.get("kind") != "Overruled":
                continue
            binding = next((b for b in store.get("bindings", []) + after.get("bindings", [])
                            if b["collection"] == run["collection"] and b["handle"] == event.get("handle")), None)
            item = after_items.get((run["collection"], (binding or {}).get("link_id")), {})
            if item.get("deleted") == 0:
                require(f"{label}: Overruled {event['handle']} under {policies[run['collection']]} settles for a body, never for one nobody read", item.get("object") is not None)
    # A source's policy settles a divergence once its body is read (SYNC.md
    # sections 5 and 6): an upgrade under prefer-local, content pushes allowed,
    # or prefer-remote leaves no binding of its source holding a fetched
    # diverging body.
    policy = run.get("options", {}).get("conflict")
    pushable = run.get("options", {}).get("push", True) and run.get("options", {}).get("rights", {}).get("content", True)
    if run.get("verb") == "upgrade" and (policy == "prefer-remote" or (policy == "prefer-local" and pushable)):
        for binding in after.get("bindings", []):
            if binding["source"] == run["source"] and binding.get("conflicted") == 1:
                require(f"{label}: binding {binding['handle']} under {policy} is settled once its diverging body is read", binding.get("conflict_object") is None)
    # An Update gated on another revision than the base the binding held, a
    # policy's push over the server's body or a revived row's, is gated on one
    # whose body the run read, a member carrying it or a fetch answering it,
    # never on one nobody read; a body read and pushed over is kept, a retained
    # item holding it (SYNC.md sections 5 and 6, STORAGE.md section 11.1). A
    # local edit over a base naming its revision and no body is not judged
    # here.
    based = {b["handle"]: b for b in store.get("bindings", [])
             if b["collection"] == run["collection"] and b["source"] == run["source"]}
    fixtures_of = {object_label: spec["body"] for object_label, spec in store.get("objects", {}).items()}
    for page in pages:
        for member in page["items"]:
            if "carries" in member:
                require(f"{label}: member {member['handle']} carries a body only from a DAV kind", isinstance(member["carries"], bool)
                        and all(c["kind"] in ("text/vcard", "text/calendar") for c in store.get("collections", [])))
    for push in case["expect"].get("pushes", []):
        if push.get("kind") != "Update":
            continue
        gate = push.get("if_match")
        base = based.get(push["handle"], {})
        agreed = bool(base) and base.get("base_revision") == gate
        carried = [member for page in pages for member in page["items"]
                   if member["handle"] == push["handle"] and member.get("revision") == gate and member.get("carries") is True]
        fetched = any(answer.get("revision") == gate and answer.get("body")
                      for answer in remote.get("fetch", {}).get(push["handle"], {}).values())
        require(f"{label}: Update {push['handle']} is gated on a revision whose body was agreed or read, never pushed over an edit nobody read",
                agreed or carried or fetched)
        if carried and not agreed and "items" in after:
            body = carried[0]["meta"]["body"]
            require(f"{label}: Update {push['handle']} pushed over a body it read keeps that body",
                    any(fixtures_of.get(item.get("object")) == body and item.get("retained") is True for item in after["items"]))
    options = run.get("options", {})
    row = next((s for s in store.get("sources", []) if s["collection"] == run["collection"] and s["source"] == run["source"]), {})
    listed = {member["handle"] for page in pages for member in page["items"]}
    vanished = {handle for page in pages for handle in page.get("vanished", [])}
    interrupted = remote.get("interrupted_after")
    if remote.get("pages"):
        closes = remote["pages"][-1].get("last") is True and (interrupted is None or interrupted >= len(remote["pages"]))
    else:
        closes = bool(remote.get("snapshot") and remote["snapshot"].get("complete"))
    closes = closes and not case["expect"].get("failed") and run.get("verb") == "sync"
    scope = options.get("scope") or {"since": row.get("round_since"), "until": row.get("round_until")}
    band = row.get("round_open") is True and row.get("round_band") is True
    dates = {s["link_id"]: s["row"].get("date") for s in store.get("summaries", [])
             if s["table"] == "mail_summary" and s["collection"] == run["collection"]}

    def in_scope(link_id):
        if link_id not in dates:
            return True
        date_ = dates[link_id]
        if date_ is None:
            return not band
        return (scope.get("since") is None or scope["since"] <= date_) and (scope.get("until") is None or date_ < scope["until"])

    # A narrowed listing (SYNC.md sections 4 and 5) proves the absence only of
    # a member dated before the round opened: the stored instant of an open
    # round, else the run's own. An undated or a later-dated member is absent
    # only when the last page's unfiltered enumeration lacks its handle.
    listing = remote.get("pages") or ([remote["snapshot"]] if remote.get("snapshot") else [])
    last_page = listing[-1] if listing else {}
    narrowed = last_page.get("narrowed") is True
    enumerated = last_page.get("enumerated")
    opened = (row.get("round_started_at") if row.get("round_open") else None) or \
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    for at, page in enumerate(listing):
        require(f"{label}: page {at} of a narrowed listing says so, as every page of the round does", page.get("narrowed", False) == narrowed)
        require(f"{label}: page {at} hands an enumeration only as the last page of a narrowed round",
                "enumerated" not in page or (page is last_page and narrowed and isinstance(page["enumerated"], list)))
        require(f"{label}: page {at} is narrowed only on a mail collection, by a date filter", not page.get("narrowed")
                or all(c["kind"] == "message/rfc822" for c in store.get("collections", [])))

    def provable(binding):
        if not narrowed:
            return True
        date_ = dates.get(binding["link_id"])
        if date_ is not None and date_ < opened:
            return True
        return enumerated is not None and binding["handle"] not in enumerated

    held = {(item["collection"], item["link_id"]) for item in store.get("items", []) if item.get("deleted") == 1}
    bound = [binding for binding in store.get("bindings", [])
             if binding["collection"] == run["collection"] and binding["source"] == run["source"]
             and binding.get("base_present", 0) == 1 and in_scope(binding["link_id"])]
    absent = [binding for binding in bound if binding["handle"] not in listed | vanished
              and (binding["collection"], binding["link_id"]) not in held and provable(binding)]
    # A round that named no member, none of its pages, heads nor earlier runs
    # stamping a binding with its id, parks while any based binding is absent,
    # whatever their number (SYNC.md section 5, an empty listing).
    named = bool(listed) or (row.get("round_open") is True and any(
        binding.get("round") == row.get("round") for binding in store.get("bindings", [])
        if binding["collection"] == run["collection"] and binding["source"] == run["source"]))
    mass = ((len(bound) >= 20 and 2 * len(absent) > len(bound)) or (not named and absent)) \
        and not options.get("accept_absences")
    parked = case["expect"].get("parked")
    # A rekey (SYNC.md section 8) lists the whole collection, so a based
    # binding of the run's source that no member resolves to by link id is
    # absent, and the same guard parks it, writing nothing.
    rekey = run.get("verb") == "rekey"
    if rekey:
        resolved = {links_of_fixtures.get(member.get("meta", {}).get("body")) for page in pages for member in page["items"]}
        bound = [binding for binding in store.get("bindings", [])
                 if binding["collection"] == run["collection"] and binding["source"] == run["source"]
                 and binding.get("base_present", 0) == 1]
        absent = [binding for binding in bound if binding["link_id"] not in resolved
                  and (binding["collection"], binding["link_id"]) not in held]
        mass = ((len(bound) >= 20 and 2 * len(absent) > len(bound)) or (not listed and absent)) \
            and not options.get("accept_absences")
        closes = not case["expect"].get("failed")
    if mass and closes:
        require(f"{label}: a mass absence, or any from a listing naming no member, parks", parked == {"absent": len(absent), "bound": len(bound)})
    if parked is not None:
        require(f"{label}: only a mass absence, or one from a listing naming no member, parks", mass and closes)
        if rekey:
            for rows in ("bindings", "sources", "collections"):
                require(f"{label}: a parked rekey writes nothing to {rows}", after.get(rows, store.get(rows)) == store.get(rows))
        else:
            require(f"{label}: a parked round stays open", any(s.get("round_open") is True for s in after.get("sources", [])
                                                                if s["source"] == run["source"]))
    if "bindings" in after and run.get("verb") != "rekey":
        kept = {binding["link_id"] for binding in after["bindings"]
                if binding["collection"] == run["collection"] and binding["source"] == run["source"]}
        for binding in store.get("bindings", []):
            if binding["collection"] != run["collection"] or binding["source"] != run["source"]:
                continue
            if binding.get("base_present", 0) != 1 or binding["link_id"] in kept:
                continue
            stated = binding["handle"] in vanished or binding["handle"] in staged or binding["handle"] in listed
            inferred = closes and parked is None and not mass and binding in absent
            require(f"{label}: binding {binding['handle']} leaves only for a stated removal or a closed round's absence in scope", stated or inferred)
    for binding in store.get("bindings", []) + case["expect"].get("store", {}).get("bindings", []):
        provisional = binding["handle"].startswith("\u0001")
        require(f"{label}: binding {binding['handle']!r} is provisional iff it has no base", provisional == (binding.get("base_present", 0) == 0))
        if provisional:
            check(f"{label}: provisional handle of {binding['link_id']}", binding["handle"], "\u0001" + binding["link_id"])

    # Every push is keyed as SYNC.md section 4 says, its object named under
    # blake3 for the derivation, so an engine's keys are checked against the
    # prose and never against another engine.
    names = {object_label: name(blake3((root / spec["body"]).read_bytes()).digest()) for object_label, spec in store.get("objects", {}).items()}
    # A body whose bytes fail its name, or with no blob, is no body (STORAGE
    # section 7): no push carries it.
    unread = {object_label for object_label, spec in store.get("objects", {}).items() if spec.get("corrupt") or spec.get("blob") is False}
    for push in case["expect"].get("pushes", []):
        require(f"{label}: push {push.get('handle')} carries no body it could not verify", push.get("object") not in unread)
    # A conflict is settled by an overrule or by a person's resolution naming
    # it (SYNC.md section 7, STORAGE.md section 15.3): an Edit stating no
    # overrule that meets the item's conflict or its binding's, unless its
    # resolves names each one's diverging body, or that states resolves and
    # meets none, is refused, the rows as they were.
    mutation = run.get("mutation", {}) if run.get("verb") == "mutate" else {}
    if mutation.get("kind") == "Edit" and not mutation.get("overrule"):
        item = next((i for i in store.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
        binding = next((b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                        and b["link_id"] == item.get("link_id") and b["source"] == run["source"]), {})
        met = [row.get("conflict_object") for row in (item, binding) if row.get("conflicted") == 1]
        resolves = mutation.get("resolves")
        if (met and any(body is None or body not in (resolves or []) for body in met)) or (resolves is not None and not met):
            require(f"{label}: an Edit settling a conflict nobody resolved, or resolving one that does not stand, fails", case["expect"].get("failed") is True)
            for table in ("items", "bindings"):
                check(f"{label}: a refused resolution leaves the {table} as they were", after.get(table, store.get(table)), store.get(table))
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
        # An add accepted with no handle (SYNC.md section 4) names no member:
        # its create stays pending under the provisional handle until a page
        # lands it.
        if outcome.get("outcome") == "Accepted" and "assigned" in outcome and outcome["assigned"] is None and outcome.get("handle", "").startswith("\u0001"):
            require(f"{label}: an add accepted without a handle keeps its provisional binding",
                    any(binding["handle"] == outcome["handle"] for binding in case["expect"].get("store", {}).get("bindings", [])))

# The search cases (SEARCH.md section 11): every fixture and placement resolves.
search = root / "search"
store = json.loads((search / "store.json").read_text())
queries = json.loads((search / "queries.json").read_text())

# The limits of a query (SEARCH.md section 8.3), read from its table, so the
# parser above refuses what the prose bounds and a number the prose moves
# moves here.
search_md = (root.parent / "SEARCH.md").read_text()
limits_table = search_md.split("| Limit | Bound |")[1].split("\n\n")[0]
LIMITS = {row.split("|")[1].strip(): int(row.split("|")[2].split()[0].replace(",", ""))
          for row in limits_table.splitlines()[2:]}
check("search limits: the table states length, nesting and terms", sorted(LIMITS), ["length", "nesting", "terms"])
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

for collection in store["collections"]:
    require(f"search store: {collection['id']} has a kind of the set", collection["kind"] in KINDS)

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
KEYS = {"query", "hits", "threads", "error", "sort", "ordered", "horizon_left", "temporal", "cut", "note"}
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
    left = None if "error" in case else horizon_left_of(case["query"], store["collections"], instant(queries["now"]), queries["horizon"])
    if left is not None:
        check(f"{label}: horizon_left", case.get("horizon_left", False), left)
    try:
        parse(case["query"])
        got = None
    except Refused as refused:
        got = {"code": refused.code, "start": refused.start, "end": refused.end}
    if "error" in case:
        require(f"{label}: refusals carry no sort, order or coverage", not set(case) & {"sort", "ordered", "horizon_left", "temporal", "cut"})
        require(f"{label}: a known code", case["error"].get("code") in CODES)
        check(f"{label}: refusal", got, case["error"])
    else:
        check(f"{label}: accepted", got, None)

# The task views of Pimalaya's GTD convention (conventions/gtd.md section
# 1): each query of its table is a case, and its hits are re-derived from the
# fixtures' bytes, a task's status and categories read by task_columns' second
# path, never by the query.
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
guide = (root.parent / "conventions" / "gtd.md").read_text().split("## 1. Tasks by categories")[1].split("\n## ")[0]
view_queries = dict(re.findall(r"^\| (\w+) \| `([^`]+)` \|$", guide, re.M))
check("gtd views: conventions/gtd.md's table names the four", sorted(view_queries), sorted(VIEWS))
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

# The occurrence windows (SEARCH.md section 7, occurrences_between): each row
# an item of a calendar collection, inside the horizon, overlapping its window
# on section 8.1's rule, and the rows in the statement's order; only an
# implementation expands the series.
calendar_items = {(item["collection"], item["seq"]) for item in store["items"]
                  if any(c["id"] == item["collection"] and c["kind"] == "text/calendar" for c in store["collections"])}
horizon = (instant(queries["horizon"]["start"]), instant(queries["horizon"]["end"]))
for window in queries["occurrences"]:
    label = f"occurrences {window['start']}..{window['end']}"
    low, high = instant(window["start"]), instant(window["end"])
    require(f"{label}: a range", low < high)
    require(f"{label}: inside the horizon", horizon[0] <= low and high <= horizon[1])
    for collection, seq, start, end in window["rows"]:
        require(f"{label}: {collection} {seq} is a calendar item", (collection, seq) in calendar_items)
        begins, ends = instant(start), instant(end)
        require(f"{label}: {collection} {seq} at {start} ends after it starts or with it", begins <= ends)
        require(f"{label}: {collection} {seq} at {start} overlaps the range",
                begins < high and (ends > low or begins >= low))
    order = [(instant(start), seq, collection) for collection, seq, start, end in window["rows"]]
    check(f"{label}: rows by start, seq, collection", order, sorted(order))

# Text terms (SEARCH.md section 8.5), compiled for the canonical shape and run
# on an FTS5 table of the fixture store's titles (section 6), folded as
# section 5 says: a case whose query is one text term on the title field has
# its hits re-derived. A case whose term holds FTS5 syntax must be one the
# term's text spliced raw answers otherwise, or refuses, so the vectors keep
# telling a compiler from a splice.
def fold(text):
    decomposed = unicodedata.normalize("NFD", text.lower())
    return unicodedata.normalize("NFC", "".join(c for c in decomposed if not "̀" <= c <= "ͯ"))


def fts_term(column, text, prefix):
    """One FTS5 string, its `"` doubled, a prefix starred, filtered to a
    column (SEARCH.md section 8.5)."""
    expression = '"' + fold(text).replace('"', '""') + '"' + (" *" if prefix else "")
    return f"{{{column}}} : {expression}" if column else expression


def unescaped(value):
    return re.sub(r"\\([\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def title_of(item):
    """The title field (SEARCH.md section 6): a message's Subject, a card's
    FN, N components and NICKNAME, a calendar component's SUMMARY, a
    bodiless item's summary."""
    if "summary" in item:
        row = item["summary"]["row"]
        return next((row[column] for column in ("subject", "fn", "summary", "name") if row.get(column)), "")
    bytes_ = (root / item["fixture"]).read_bytes()
    if kinds[item["collection"]] == "message/rfc822":
        return mail_columns(bytes_)["subject"]
    titles = []

    def walk(component):
        name, properties, children = component
        for prop, _, value in properties:
            if name == "VCARD" and prop == "N":
                titles.extend(unescaped(part) for part in re.split(r"(?<!\\);", value) if part)
            elif (name == "VCARD" and prop in ("FN", "NICKNAME")) or (
                    name in ("VEVENT", "VTODO", "VJOURNAL") and prop == "SUMMARY"):
                titles.extend(unescaped(part) for part in re.split(r"(?<!\\),", value) if part)
        for child in children:
            walk(child)

    walk(components(bytes_))
    return "\n".join(titles)


titles = sqlite3.connect(":memory:")
titles.execute("CREATE VIRTUAL TABLE t USING fts5(title, tokenize = 'unicode61 remove_diacritics 0', prefix = '2 3')")
titled = list(enumerate(store["items"], 1))
titles.executemany("INSERT INTO t(rowid, title) VALUES (?, ?)", [(at, fold(title_of(item))) for at, item in titled])


def title_hits(expression):
    rows = titles.execute("SELECT rowid FROM t WHERE t MATCH ?", (expression,)).fetchall()
    return sorted([accounts[titled[at - 1][1]["collection"]], titled[at - 1][1]["seq"]] for at, in rows)


FTS5_SYNTAX = re.compile(r'[\^+{}():*"-]|\b(AND|OR|NOT|NEAR)\b')
title_cases = 0
for case in queries["cases"]:
    if "hits" not in case:
        continue
    tokens = lex(case["query"])
    if len(tokens) != 1 or tokens[0]["kind"] != "field":
        continue
    token = tokens[0]
    if case["query"][token["start"]:token["colon"]] not in ("subject", "title", "summary"):
        continue
    value = case["query"][token["colon"] + 1:token["end"]]
    text = value[1:-1] if token["phrase"] else value
    prefix = not token["phrase"] and text.endswith("*")
    label = f"search {case['query']!r}"
    try:
        compiled = title_hits(fts_term("title", text[:-1] if prefix else text, prefix))
    except sqlite3.OperationalError as error:
        compiled = f"refused by FTS5: {error}"
    check(f"{label}: the title term's hits (section 8.5)", sorted(case["hits"]), compiled)
    title_cases += 1
    if FTS5_SYNTAX.search(text):
        try:
            raw = title_hits(f"{{title}} : {text}")
        except sqlite3.OperationalError:
            raw = None
        require(f"{label}: holds FTS5 syntax that its text spliced raw answers alike", raw != sorted(case["hits"]))
require("search: a text term holding FTS5 syntax is re-derived", title_cases >= 9)

# The bounds of SEARCH.md section 7, read from its prose, and a second path
# expanding a series a simple rule states: one VEVENT, a UTC DTSTART, a
# DURATION, an RRULE stepping by the second, the minute, the hour or the day
# whose BYxxx parts only limit, no COUNT, UNTIL, RDATE, EXDATE nor override.
# Its occurrences in the windows, and the cut a case reaching it counts,
# follow the bounds; every other calendar item of the store states a bounded
# series and is never cut.
bounds = re.search(r"An item writes at most ([\d,]+) occurrences.*?examines at most ([\d,]+) periods", search_md)
OCCURRENCES, PERIODS = (int(number.replace(",", "")) for number in bounds.groups())
# The BYxxx parts that limit a rule of each step (RFC 5545 section 3.3.10).
LIMITING = {
    "SECONDLY": {"BYMONTH", "BYMONTHDAY", "BYHOUR", "BYMINUTE", "BYSECOND"},
    "MINUTELY": {"BYMONTH", "BYMONTHDAY", "BYHOUR", "BYMINUTE"},
    "HOURLY": {"BYMONTH", "BYMONTHDAY", "BYHOUR"},
    "DAILY": {"BYMONTH", "BYMONTHDAY"},
}


def epoch(text):
    return int(instant(text).timestamp())


def stamp(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def simple_series(bytes_, horizon):
    """The occurrences a simple rule writes inside the horizon, as (start,
    end) instants, and its cut, or None for any other resource."""
    found = [c for c in components(bytes_)[2][0][2] if c[0] in ("VEVENT", "VTODO", "VJOURNAL")]
    if len(found) != 1 or found[0][0] != "VEVENT":
        return None
    properties = {prop: (params, value) for prop, params, value in found[0][1]}
    start, duration = properties.get("DTSTART"), properties.get("DURATION")
    if ("RRULE" not in properties or {"RDATE", "EXDATE", "RECURRENCE-ID"} & set(properties)
            or start is None or start[0] or not re.fullmatch(r"\d{8}T\d{6}Z", start[1])
            or duration is None or not re.fullmatch(r"PT\d+[HMS]", duration[1])):
        return None
    rule = dict(part.split("=", 1) for part in properties["RRULE"][1].split(";"))
    frequency = rule.pop("FREQ", None)
    step = STEPS.get(frequency, 0) * int(rule.pop("INTERVAL", "1"))
    if not step or set(rule) - LIMITING[frequency]:
        return None
    sets = {part: {int(value) for value in values.split(",")} for part, values in rule.items()}
    length = int(duration[1][2:-1]) * {"H": 3600, "M": 60, "S": 1}[duration[1][-1]]
    first = epoch(f"{start[1][0:4]}-{start[1][4:6]}-{start[1][6:8]}T{start[1][9:11]}:{start[1][11:13]}:{start[1][13:15]}Z")
    low, high = horizon
    written, cut = [], None
    for period in range(PERIODS + 1):
        at = first + period * step
        if period == PERIODS:
            cut = at
            break
        if at >= high:
            break
        day, clock = divmod(at, 86400)
        hour, rest = divmod(clock, 3600)
        if not (hour in sets.get("BYHOUR", {hour}) and rest // 60 in sets.get("BYMINUTE", {rest // 60})
                and rest % 60 in sets.get("BYSECOND", {rest % 60})):
            continue
        when = datetime.fromtimestamp(at, timezone.utc)
        if when.month not in sets.get("BYMONTH", {when.month}) or when.day not in sets.get("BYMONTHDAY", {when.day}):
            continue
        if at < high and at + length > low:
            if len(written) == OCCURRENCES:
                cut = at
                break
            written.append((at, at + length))
    return [(stamp(a), stamp(b)) for a, b in written], (stamp(cut) if cut is not None else None)


window = (epoch(queries["horizon"]["start"]), epoch(queries["horizon"]["end"]))
series = {}
for item in store["items"]:
    if "fixture" not in item or kinds[item["collection"]] != "text/calendar":
        continue
    bytes_ = (root / item["fixture"]).read_bytes()
    derived = simple_series(bytes_, window)
    if derived is not None:
        series[(item["collection"], item["seq"])] = derived
        continue
    rules = [value for name, _, children in [components(bytes_)[2][0]] for c in children
             if c[0] in ("VEVENT", "VTODO", "VJOURNAL") for prop, _, value in c[1] if prop == "RRULE"]
    require(f"search store: {item['fixture']} states a bounded series, never cut",
            all("UNTIL=" in rule or "COUNT=" in rule for rule in rules))
require("search store: a series meets each bound of section 7",
        {cut is not None for _, cut in series.values()} == {True} and len(series) >= 2)

for window_case in queries["occurrences"]:
    low, high = window_case["start"], window_case["end"]
    for key, (rows, _) in series.items():
        derived = [[key[0], key[1], start, end] for start, end in rows
                   if instant(start) < instant(high) and (instant(end) > instant(low) or instant(start) >= instant(low))]
        check(f"occurrences {low}..{high}: {key[0]} {key[1]}, expanded within section 7's bounds",
              [row for row in window_case["rows"] if (row[0], row[1]) == key], derived)


def cut_of(query, collections, now):
    """The cut a plain query of kind:, collection:, account: and date: terms
    reports (SEARCH.md section 8.2): the series of its collections cut
    before its range's end. None for a query this does not read."""
    scope, end, kinds_named = list(collections), None, set()
    for word in query.split():
        name, _, value = word.partition(":")
        if name == "kind":
            kinds_named.add(value)
        elif name in ("collection", "folder"):
            scope = [c for c in scope if c["id"] == value]
        elif name == "account":
            scope = [c for c in scope if c["account"] == value]
        elif name in ("date", "when") and ".." not in value:
            end = point_span(value, now)[1]
        else:
            return None
    if end is None:
        return None
    media = {"mail": "message/rfc822", "contact": "text/vcard", "event": "text/calendar", "task": "text/calendar",
             "journal": "text/calendar", "file": "application/octet-stream"}
    if kinds_named:
        scope = [c for c in scope if c["kind"] in {media[k] for k in kinds_named}]
    ids = {c["id"] for c in scope}
    return sum(1 for (collection, _), (_, cut) in series.items()
               if collection in ids and cut is not None and instant(cut) < end)


for case in queries["cases"]:
    if "cut" in case:
        label = f"search {case['query']!r}"
        require(f"{label}: cut is a count", isinstance(case["cut"], int) and case["cut"] >= 0)
        derived = cut_of(case["query"], store["collections"], instant(queries["now"]))
        require(f"{label}: a cut case is one checks/vectors.py re-derives", derived is not None)
        check(f"{label}: cut", case["cut"], derived)

# The task writers (conventions/gtd.md section 1): every case's shape and
# references, and what its edit may change, re-derived from the bytes on both
# sides by a second path, so an expected fixture that touches a line the
# guide keeps, or writes a state or a category the edit did not ask for, fails
# here.
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


gtd_dir = root.parent / "conventions" / "gtd"
writers = json.loads((gtd_dir / "writers.json").read_text())
require("gtd writers: states its format's version v", isinstance(writers.get("v"), int))
for error in Draft202012Validator(json.loads((gtd_dir / "writers.schema.json").read_text())).iter_errors(writers):
    failures.append(f"conventions/gtd/writers.json: {error.json_path}: {error.message}")
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

# The chunk cases (SEARCH.md section 6): every boundary re-derived from the
# rule.
chunk_cases = json.loads((search / "chunks.json").read_text())["cases"]
for case in chunk_cases:
    derived = []
    for field in ("body", "note"):
        for start, end in chunk(text_of(case["fields"].get(field, []))):
            derived.append({"ord": len(derived), "field": field, "start": start, "end": end})
    check(f"chunks {case['label']!r}", derived, case["chunks"])

# Every fixture is a body some case names (summaries.json, a sync case, the
# search store), so none lies under vectors/fixtures/ that no rule reads.
named = {match for path in [root / "summaries.json", *sync_cases, search / "store.json"]
         for match in re.findall(r'"(fixtures/[^"]+)"', path.read_text())}
for path in sorted((root / "fixtures").iterdir()):
    require(f"vectors/fixtures/{path.name}: a fixture no case names", f"fixtures/{path.name}" in named)

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print(
    f"{len(objects['base32']['cases'])} base32 cases, "
    f"{len(objects['objects'])} object names, "
    f"{len(summaries['cases'])} summaries over {len(fixtures)} fixtures, "
    f"{sum('hint' in case for case in summaries['cases'])} minted link ids, "
    f"{len(sync_cases)} sync cases, {len(queries['cases'])} search cases, {len(chunk_cases)} chunk cases, "
    f"{len(writers['cases'])} task writer cases, {len(payload_cases)} payloads and {enqueued} scenario payloads check, "
    f"every file the manifest's"
)
