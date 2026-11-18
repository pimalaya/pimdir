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
# The text fields whose value holding an @ is an address, no text term
# (SEARCH.md sections 8, 8.3): the role fields and with:.
ADDRESS_FIELDS = {"from", "to", "cc", "bcc", "attendee", "organizer", "email", "with"}
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
    amount = re.fullmatch(r"(\d+)[dwy]", value)
    if re.fullmatch(r"\d{4}", value) or value in {"today", "yesterday"} or (amount and len(amount.group(1)) <= DIGITS["relative"]):
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
        check_wildcard(value, colon + 1, name in TEXT_FIELDS and not (name in ADDRESS_FIELDS and "@" in value))
    if name in CLOSED_FIELDS and value not in CLOSED_FIELDS[name]:
        raise Refused("invalid-value", colon + 1, end)
    if name in DATE_FIELDS and not range_of(value, date_point):
        raise Refused("invalid-date", colon + 1, end)
    if name == "changed" and not range_of(value, lambda side: side.isascii() and side.isdigit() and len(side) <= DIGITS["stamp"]):
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
    return rollup(scope, since, until)


def rollup(scope, since, until):
    """The temporal axis over collections and a range of RFC 3339 instants,
    either side None when open."""
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


def point_span(point, now, zone=timezone.utc):
    """A point's span (SEARCH.md section 8.1), its days read in `zone`, a
    bound no instant of a four-digit year states being open, None: an end
    past 9999-12-31T23:59:59Z, a start before the year 0000.

    NOTE: Python's calendar starts at the year 0001, so a start within the
    year 0000 reads open here where the prose bounds it; every case's points
    are checked to stand clear of that year."""
    def midnight(year, month, day):
        try:
            if year > 9999:
                # The midnight ending 9999, a day after the one starting its
                # last day, which no transition moves.
                return datetime(9999, 12, 31, tzinfo=zone).astimezone(timezone.utc) + timedelta(days=1)
            return datetime(year, month, day, tzinfo=zone).astimezone(timezone.utc)
        except (ValueError, OverflowError):
            return None

    def day_after(day):
        return (day.year + 1, 1, 1) if (day.month, day.day) == (12, 31) else (day + timedelta(days=1)).timetuple()[:3]

    today = now.astimezone(zone).date()
    if point == "today":
        return midnight(*today.timetuple()[:3]), midnight(*day_after(today))
    if point == "yesterday":
        return midnight(*(today - timedelta(days=1)).timetuple()[:3]), midnight(*today.timetuple()[:3])
    amount = re.fullmatch(r"(\d+)([dwy])", point)
    if amount:
        n, unit = int(amount.group(1)), amount.group(2)
        try:
            start = now.replace(year=now.year - n) if unit == "y" else now - timedelta(days=n * (7 if unit == "w" else 1))
        except (ValueError, OverflowError):
            start = None
        return start, now
    if re.fullmatch(r"\d{4}", point):
        return midnight(int(point), 1, 1), midnight(int(point) + 1, 1, 1)
    if re.fullmatch(r"\d{4}-\d{2}", point):
        year, month = int(point[:4]), int(point[5:])
        return midnight(year, month, 1), midnight(year + month // 12, month % 12 + 1, 1)
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", point):
        day = date.fromisoformat(point)
        return midnight(day.year, day.month, day.day), midnight(*day_after(day))
    return None, None


def horizon_left_of(query, collections, now, horizon, zone=timezone.utc):
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
    start = point_span(low, now, zone)[0] if low else None
    end = point_span(high, now, zone)[1] if high else None
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
    space or a tab is removed, the whitespace kept. A field line splits at
    its first colon, its name the bytes before it trimmed of trailing spaces
    and tabs, and a line holding no colon is no field."""
    if bytes_.endswith(b"\r"):
        bytes_ += b"\n"
    block = re.split(rb"\r?\n\r?\n", bytes_, maxsplit=1)[0]
    unfolded = re.sub(rb"\r?\n(?=[ \t])", b"", block)
    fields = []
    for line in re.split(rb"\r?\n", unfolded):
        name, colon, value = line.partition(b":")
        if colon:
            fields.append((name.rstrip(b" \t").decode("ascii", "replace").lower(), value))
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
ISO_8859_2_LABELS = {"csisolatin2", "iso-8859-2", "iso-ir-101", "iso8859-2", "iso88592", "iso_8859-2", "iso_8859-2:1987", "l2", "latin2"}
ISO_2022_JP_LABELS = {"csiso2022jp", "iso-2022-jp"}
GBK_LABELS = {"chinese", "csgb2312", "csiso58gb231280", "gb2312", "gb_2312", "gb_2312-80", "gbk", "iso-ir-58", "x-gbk"}


# The standard library's codecs are not the Encoding Standard's decoders, so
# each is used only over the octets where the two provably agree, and octets
# outside them fail the run rather than read as either:
# - iso8859_2 holds the standard's index-iso-8859-2 above 7F whole, the C1
#   controls at 80 to 9F included, and ASCII below.
# - iso2022_jp is read between ESC $ B and ESC ( B alone, over JIS X 0208
#   rows 4 and 5, the kana, and 16 to 84, the kanji: never ESC ( J, whose 5C
#   and 7E the standard reads as the yen sign and the overline, ESC ( I, the
#   katakana the codec refuses, ESC $ @, rows 1 and 2, where the standard's
#   index maps five symbols to their fullwidth forms, nor row 13 and those
#   from 89 up, the extensions its index adds.
# - gbk is read over ASCII and the pairs of GB 2312's rows of characters, a
#   lead of B0 to F7 before a trail of A1 to FE: never the octet 80, the
#   standard's euro sign, a four-octet sequence, which its gbk decoder reads
#   as gb18030 does, nor a pair the gb18030 index maps apart (A2E3, A6D9 to
#   A6F3, A8BC, A8BF, FE50 to FEA0).
def agreed_octets(codec, octets):
    if codec == "iso8859_2":
        return True
    if codec == "iso2022_jp":
        runs = re.fullmatch(rb"(?:[\x00-\x1a\x1c-\x7f]|\x1b\$B(?:[\x24\x25\x30-\x74][\x21-\x7e])*\x1b\(B)*", octets)
        return runs is not None
    if codec == "gbk":
        return re.fullmatch(rb"(?:[\x00-\x7f]|[\xb0-\xf7][\xa1-\xfe])*", octets) is not None
    return False


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
    for labels, codec in ((ISO_8859_2_LABELS, "iso8859_2"), (ISO_2022_JP_LABELS, "iso2022_jp"), (GBK_LABELS, "gbk")):
        if label in labels:
            if not agreed_octets(codec, octets):
                failures.append(f"charset {label}: octets {octets.hex()} outside those checks/vectors.py decodes as the Encoding Standard does")
                return None
            return octets.decode(codec)
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


def summarized(calendar_):
    """The component a resource's row is read from (Annex A.3): the master,
    the first VEVENT, VTODO or VJOURNAL carrying no RECURRENCE-ID, else, in a
    resource holding overrides alone, the first carrying one, in document
    order; None when it holds none of the three."""
    found = [c for c in calendar_[2] if c[0] in ("VEVENT", "VTODO", "VJOURNAL")]
    masters = [c for c in found if calendar_property(c, "RECURRENCE-ID") is None]
    return (masters or found or [None])[0]


def calendar_sort_key(bytes_):
    """Annex A.3 to A.5's sort key: the DTSTART of the component the row is
    read from, a task's DUE before it, as an instant, '' when none reads as
    one."""
    calendar_ = components(bytes_)[2][0]
    vtimezones = {calendar_property(c, "TZID")[1]: c for c in calendar_[2] if c[0] == "VTIMEZONE"}
    master = summarized(calendar_)
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


# The characters of the White_Space property of Unicode 15.0.0 (PropList.txt),
# the set Annex A.2 trims a sort key of. str.strip() with no argument would
# also take U+001C to U+001F, which the property does not hold.
WHITE_SPACE = "".join(map(chr, [*range(0x09, 0x0E), 0x20, 0x85, 0xA0, 0x1680, *range(0x2000, 0x200B),
                                0x2028, 0x2029, 0x202F, 0x205F, 0x3000]))


def folded(text):
    """Annex A.2's lowercase: the default full mapping with Final_Sigma and
    no other conditional mapping, which is str.lower(). The interpreter's
    Unicode version may be later than 15.0.0, whose case pairs are stable."""
    return text.lower()


def usable(hint):
    """Whether a hint is usable (STORAGE section 9): stated, and not empty
    once trimmed of the space and the tab."""
    return hint is not None and hint.strip(" \t") != ""


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
    addresses = [("email", position, folded(value), None)
                 for position, value in enumerate(value for prop, value in props if prop == "EMAIL")]
    return columns, addresses, folded(columns["fn"]).strip(WHITE_SPACE)


def calendar_rows(bytes_):
    """Annex A.3 to A.5's columns read from the master component, else from
    the first override, verbatim or decoded, and its ORGANIZER and ATTENDEE
    rows (A.3, A.6), by the reader above; the task columns task_columns()
    derives are left to it."""
    calendar_ = components(bytes_)[2][0]
    master = summarized(calendar_)

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
    "payloads.json": "payloads", "manifest.json": "manifest", "versions.json": "versions",
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

# The order of format versions (STORAGE.md section 4.2): none first, then the
# drafts by the decimal number after storage-draft-, then the releases by a
# major written without a leading zero; any other marker is read neither way.
def format_rank(marker):
    if marker is None:
        return (0, 0)
    if marker.startswith("storage-draft-"):
        number = marker[len("storage-draft-"):]
        return (1, int(number)) if number.isascii() and number.isdigit() else None
    if marker.startswith("storage-v"):
        major = marker[len("storage-v"):]
        canonical = major.isascii() and major.isdigit() and not major.startswith("0")
        return (2, int(major)) if canonical else None
    return None


versions = json.loads((root / "versions.json").read_text())
for case in versions["cases"]:
    found, own = format_rank(case["found"]), format_rank(case["own"])
    order = "unknown" if found is None or own is None else "earlier" if found < own else "later" if found > own else "same"
    check(f"versions.json: {case['found']!r} against {case['own']}", case["order"], order)
for order in ("earlier", "same", "later", "unknown"):
    require(f"versions.json: a case of a store {order}", any(case["order"] == order for case in versions["cases"]))

# A summary row in any format names the columns of its table in the canonical
# schema (STORAGE.md section 4.3), read off migrations/storage/, a list column
# standing for its child table (mail_in_reply_to as in_reply_to, task_category
# as categories), so a column misspelt or dropped in a format's $defs, or in
# the columns read below, fails here.
store_schema = sqlite3.connect(":memory:")
for migration in sorted((root.parent / "migrations" / "storage").glob("*.sql")):
    store_schema.executescript(migration.read_text())
SQL_TABLES = {table: {row[0] for row in store_schema.execute("SELECT name FROM pragma_table_info(?)", (table,))} - {"collection", "link_id", "item"}
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
# one of two. Every case of payloads.json states the outcome its action's
# schema gives it, valid or malformed, or unknown where its action and v name
# no schema, so a schema loosened, a malformed payload or a version read as
# another fails here.
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


known_actions = {action_version.rsplit(".v", 1)[0] for action_version in payload_schemas}


def payload_outcome(action, payload):
    """A payload's outcome for an owner and a producer of this version
    (STORAGE.md sections 15.2 and 15.3): one whose action and v name a schema
    under payloads/ is valid when that schema accepts it and malformed
    otherwise; one whose action, or whose v for a known action, names none is
    unknown, whatever else it holds. A payload of a known action stating no
    v, or one that is no integer, states no version to wait for, and is
    malformed."""
    version = payload.get("v")
    if action in known_actions and (isinstance(version, bool) or not isinstance(version, int)):
        return "malformed"
    schema = payload_schemas.get(f"{action}.v{version}")
    if schema is None:
        return "unknown"
    return "malformed" if list(Draft202012Validator(schema).iter_errors(payload)) else "valid"


for index, case in enumerate(payload_cases):
    check(f"payloads.json case {index} ({case['action']}, {case.get('note', 'valid')}) outcome",
          case["outcome"], payload_outcome(case["action"], case["payload"]))
for action_version in payload_schemas:
    require(f"payloads.json: a valid and a malformed {action_version}",
            {case["outcome"] for case in payload_cases
             if f"{case['action']}.v{case['payload'].get('v')}" == action_version} == {"valid", "malformed"})
# A known action stating no v, and one stating a v that is no integer, are
# malformed, while an action no schema defines stays unknown without one.
versionless = [case for case in payload_cases if "v" not in case["payload"]]
require("payloads.json: a known action stating no v, malformed",
        any(case["action"] in known_actions and case["outcome"] == "malformed" for case in versionless))
require("payloads.json: an action no schema defines stating no v, unknown",
        any(case["action"] not in known_actions and case["outcome"] == "unknown" for case in versionless))
require("payloads.json: a known action stating a v that is no integer, as a string, a fraction, a boolean and null",
        {type(case["payload"]["v"]) for case in payload_cases
         if case["action"] in known_actions and "v" in case["payload"]} >= {int, str, float, bool, type(None)})
# A v written with a fraction or an exponent is no integer though its value is
# whole, which the schema alone would take as one: the reading of a JSON
# number as an integer is the text's (STORAGE.md section 15.3).
require("payloads.json: a known action stating a whole v written as no integer, 1.0 or 1e0, malformed where its schema accepts it",
        any(case["action"] in known_actions and isinstance(case["payload"].get("v"), float) and case["payload"]["v"].is_integer()
            and case["outcome"] == "malformed"
            and not list(Draft202012Validator(payload_schemas[f"{case['action']}.v{int(case['payload']['v'])}"]).iter_errors(case["payload"]))
            for case in payload_cases))
# The three ways a payload is unknown: a known action at a v no schema
# defines, an action no schema defines, and an application's own, x-.
unknown_cases = [case for case in payload_cases if case["outcome"] == "unknown"]
require("payloads.json: an unknown payload of a known action at another v",
        any(case["action"] in known_actions for case in unknown_cases))
require("payloads.json: an unknown payload of an action no schema defines",
        any(case["action"] not in known_actions and not case["action"].startswith("x-") for case in unknown_cases))
require("payloads.json: an unknown payload of an application's own action",
        any(case["action"].startswith("x-") for case in unknown_cases))


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
# payload` heads, which must be malformed, and one a comment opening `# An
# unknown payload` heads, whose action and v must name no schema.
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
    heading = harness.splitlines()[above + 1].lstrip()
    stated = "malformed" if heading.startswith("# A malformed payload") else \
        "unknown" if heading.startswith("# An unknown payload") else "valid"
    document = json.loads(shell_word(payload.group(1)))
    check(f"checks/invariants.sh: the {action.group(1)} payload {json.dumps(document)[:60]} outcome",
          payload_outcome(action.group(1), document), stated)
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

    # A resource stating no usable UID, none, an empty one or one of spaces
    # and tabs alone, takes the hash: fallback over its bytes (section 9).
    if not usable(case["summary"].get("uid")) and case["table"] != "mail_summary":
        check(f"{case['label']} hash: link_id", case["link_id"], "hash:" + fnv1a(bytes_))

    # A stated identity is the link id verbatim, escaped when it begins with a
    # prefix the writer derives keys under (STORAGE section 9), so a UID
    # stating hash: never reads as a key derived from the bytes.
    stated = case["summary"].get("message_id" if case["table"] == "mail_summary" else "uid")
    if usable(stated) and "hint" not in case:
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
# The cases a rule needs to be held at all: a Move over each conflict, an
# Abandon beside another source binding the item, a capped rekey, a dated
# member a narrowed round keeps with and without an enumeration, and a refusal
# recorded, held and cleared, an offered create bound on its refusal.
rule_cases = {"a move over the item's conflict": 0, "a move over its binding's conflict": 0, "an abandon beside another source": 0,
              "a capped rekey leaving a member out": 0,
              "a narrowed round keeping a dated member its enumeration holds": 0,
              "a narrowed round handing no enumeration keeping a dated member": 0,
              "a refusal recorded": 0, "a refused change held": 0, "a refusal cleared by an accepted push": 0,
              "an offered create bound on its refusal": 0}

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
    # An Abandon (SYNC.md section 7) drops, on request, the binding of the
    # delivered create it names, of the run's source.
    if case["run"].get("verb") == "mutate" and case["run"]["mutation"].get("kind") == "Abandon":
        staged |= {
            binding["handle"]
            for binding in store.get("bindings", [])
            for item in store.get("items", [])
            if binding["collection"] == case["run"]["collection"] and binding["source"] == case["run"]["source"]
            and item["collection"] == binding["collection"] and item["link_id"] == binding["link_id"]
            and item["seq"] == case["run"]["mutation"].get("seq")
            and binding["handle"].startswith("\u0001") and binding.get("base_present", 0) == 1
        }
    # A delivered create tombstoned since (SYNC.md sections 5 and 6) holds its
    # Remove until a page lands it, then pushes it against the listed handle.
    delivered = {
        binding["link_id"]
        for binding in store.get("bindings", [])
        for item in store.get("items", [])
        if binding["collection"] == case["run"]["collection"] and binding["handle"].startswith("\u0001")
        and binding.get("base_present", 0) == 1
        and item["collection"] == binding["collection"] and item["link_id"] == binding["link_id"] and item.get("deleted") == 1
    }
    staged |= {member["handle"] for page in pages for member in page["items"]
               if links_of_fixtures.get((member.get("meta") or {}).get("body")) in delivered}
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
        # An edit staged before the run waits (SYNC.md section 5).
        before = next((b for b in store.get("bindings", []) if b["collection"] == binding["collection"]
                       and b["source"] == binding["source"] and b["handle"] == binding["handle"]), {})
        held = next((i for i in store.get("items", []) if i["collection"] == binding["collection"]
                     and i["link_id"] == binding["link_id"]), {})
        if before.get("base_revision") == binding["base_revision"] and before.get("base_object") is None \
                and held.get("object") == item.get("object"):
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
    # item holding it (SYNC.md sections 5 and 6, STORAGE.md section 11.1).
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
        agreed = bool(base) and base.get("base_revision") == gate and base.get("base_object") is not None
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
    # a member its last page's unfiltered enumeration lacks, whatever its date,
    # and of none when that page hands no enumeration.
    listing = remote.get("pages") or ([remote["snapshot"]] if remote.get("snapshot") else [])
    last_page = listing[-1] if listing else {}
    narrowed = last_page.get("narrowed") is True
    enumerated = last_page.get("enumerated")
    capped = last_page.get("capped") is True
    for at, page in enumerate(listing):
        require(f"{label}: page {at} of a narrowed listing says so, as every page of the round does", page.get("narrowed", False) == narrowed)
        require(f"{label}: page {at} of a capped listing says so, as every page of the round does", page.get("capped", False) == capped)
        require(f"{label}: page {at} hands an enumeration only as the last page of a narrowed round",
                "enumerated" not in page or (page is last_page and narrowed and isinstance(page["enumerated"], list)))
        require(f"{label}: page {at} is narrowed only on a mail collection, by a date filter", not page.get("narrowed")
                or all(c["kind"] == "message/rfc822" for c in store.get("collections", [])))

    def provable(binding):
        if capped:
            return False
        if not narrowed:
            return True
        return enumerated is not None and binding["handle"] not in enumerated

    held = {(item["collection"], item["link_id"]) for item in store.get("items", []) if item.get("deleted") == 1}
    # A delivered create, based under its provisional handle, is no member a
    # listing names: never absent, never counted (SYNC.md sections 2 and 5).
    bound = [binding for binding in store.get("bindings", [])
             if binding["collection"] == run["collection"] and binding["source"] == run["source"]
             and binding.get("base_present", 0) == 1 and not binding["handle"].startswith("\u0001")
             and in_scope(binding["link_id"])]
    absent = [binding for binding in bound if binding["handle"] not in listed | vanished
              and (binding["collection"], binding["link_id"]) not in held and provable(binding)]
    # A dated member a narrowed round left unlisted and keeps: its enumeration
    # holds it, or the round hands none.
    if narrowed and closes:
        kept_dated = [binding for binding in bound if binding["handle"] not in listed | vanished
                      and dates.get(binding["link_id"]) is not None
                      and (enumerated is None or binding["handle"] in enumerated)]
        rule = ("a narrowed round keeping a dated member its enumeration holds" if enumerated is not None
                else "a narrowed round handing no enumeration keeping a dated member")
        rule_cases[rule] += bool(kept_dated)
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
                 and binding.get("base_present", 0) == 1 and not binding["handle"].startswith("\u0001")]
        absent = [binding for binding in bound if binding["link_id"] not in resolved
                  and (binding["collection"], binding["link_id"]) not in held]
        # A capped listing proves no absence, and an old handle names
        # nothing in the new space: a capped rekey parks on any absence.
        capped = any(page.get("capped") for page in pages)
        rule_cases["a capped rekey leaving a member out"] += bool(capped and absent)
        mass = ((len(bound) >= 20 and 2 * len(absent) > len(bound)) or (not listed and absent) or (capped and absent)) \
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
        based = binding.get("base_present", 0) == 1
        require(f"{label}: binding {binding['handle']!r} has a base unless provisional", provisional or based)
        # A delivered create holds a base naming nothing (SYNC.md section 2).
        if provisional and based:
            require(f"{label}: delivered binding {binding['handle']!r} holds a base naming nothing",
                    all(binding.get(column) is None for column in ("base_flags", "base_object", "base_revision")))
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
    # overrule, or a Remove, that meets the item's conflict or its binding's,
    # unless its resolves names each one's diverging body, or that states
    # resolves and meets none, is refused, the rows as they were. So is one
    # stating an if_match the item does not hold. A Remove that settles leaves
    # neither conflict standing, the base adopting the binding's. A Move
    # states no resolution, so one meeting a conflict is refused whatever it
    # names, its tombstone leaving the conflict under a placement nobody is
    # shown.
    mutation = run.get("mutation", {}) if run.get("verb") == "mutate" else {}
    if mutation.get("kind") in ("Edit", "Remove", "Move") and not mutation.get("overrule"):
        kind = mutation["kind"]
        item = next((i for i in store.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
        binding = next((b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                        and b["link_id"] == item.get("link_id") and b["source"] == run["source"]), {})
        met = [row.get("conflict_object") for row in (item, binding) if row.get("conflicted") == 1]
        if kind == "Move":
            rule_cases["a move over the item's conflict"] += item.get("conflicted") == 1
            rule_cases["a move over its binding's conflict"] += binding.get("conflicted") == 1
        resolves = mutation.get("resolves")
        unresolved = (met and any(body is None or body not in (resolves or []) for body in met)) or (resolves is not None and not met)
        replaced = "if_match" in mutation and item.get("object") != mutation["if_match"]
        if unresolved or replaced:
            require(f"{label}: {kind} settling a conflict nobody resolved, resolving one that does not stand, or made over a body since replaced, fails", case["expect"].get("failed") is True)
            for table in ("items", "bindings"):
                check(f"{label}: a refused {kind} leaves the {table} as they were", after.get(table, store.get(table)), store.get(table))
        elif kind == "Remove" and met and "items" in after and "bindings" in after:
            settled = next((i for i in after["items"] if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
            bound = next((b for b in after["bindings"] if b["collection"] == run["collection"]
                          and b["link_id"] == item.get("link_id") and b["source"] == run["source"]), {})
            require(f"{label}: a Remove naming the conflicts it meets tombstones the item and leaves none standing",
                    settled.get("deleted") == 1 and settled.get("conflicted", 0) == 0 and settled.get("conflict_object") is None
                    and bound.get("conflicted", 0) == 0 and bound.get("conflict_object") is None and bound.get("conflict_revision") is None)
            check(f"{label}: a Remove settling a conflict keeps the item's body under the tombstone", settled.get("object"), item.get("object"))
            if binding.get("conflicted") == 1:
                check(f"{label}: a Remove settling its binding's conflict adopts its revision and body as the base, together",
                      (bound.get("base_revision"), bound.get("base_object")), (binding.get("conflict_revision"), binding.get("conflict_object")))
    # A SetFlags (SYNC.md section 7, STORAGE.md section 15.3) carrying no base
    # replaces the set; carrying one it changes the set the placement holds,
    # adding what its flags hold and its base lacks and removing what its base
    # holds and its flags lack, and is refused over an unknown set.
    if mutation.get("kind") == "SetFlags":
        item = next((i for i in store.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
        flags, base = set(mutation["flags"]), mutation.get("base")
        if base is not None and item.get("flags") is None:
            require(f"{label}: a SetFlags stating a base over an unknown set fails", case["expect"].get("failed") is True)
            for table in ("items", "bindings"):
                check(f"{label}: a refused SetFlags leaves the {table} as they were", after.get(table, store.get(table)), store.get(table))
        elif "items" in after:
            left = flags if base is None else (set(item["flags"]) | (flags - set(base))) - (set(base) - flags)
            staged = next((i for i in after["items"] if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
            check(f"{label}: the set a SetFlags leaves", sorted(staged.get("flags") or []), sorted(left))
    # A tombstoned delivered create of a mutable kind landing on an arrival
    # that carries no body (SYNC.md sections 5 and 6): the listed revision is
    # one its base does not name, a remote edit over the tombstone, which
    # revives it. It lands live and conflicted at that revision, the base
    # naming no body and no diverging body read yet, reported Created then
    # Conflicted, and its staged Remove is not pushed.
    if run.get("verb") == "sync" and kinds.get(run["collection"]) in ("text/vcard", "text/calendar") \
            and not case["expect"].get("failed"):
        for page in pages:
            for member in page["items"]:
                if member.get("carries") is True or member.get("revision") is None:
                    continue
                link = links_of_fixtures.get((member.get("meta") or {}).get("body"))
                if link not in delivered:
                    continue
                require(f"{label}: member {member['handle']} landing a tombstoned delivered create without its body pushes no Remove",
                        all(push["handle"] != member["handle"] for push in case["expect"].get("pushes", [])))
                landed = after_items.get((run["collection"], link), {})
                bound = next((b for b in after.get("bindings", []) if b["collection"] == run["collection"]
                              and b["link_id"] == link and b["source"] == run["source"]), {})
                require(f"{label}: member {member['handle']} revives the tombstoned delivered create it lands, a remote edit over it",
                        landed.get("deleted") == 0)
                check(f"{label}: member {member['handle']} lands it conflicted at the listed revision, no body read",
                      (bound.get("handle"), bound.get("conflicted"), bound.get("conflict_revision"), bound.get("conflict_object"),
                       bound.get("base_revision"), bound.get("base_object")),
                      (member["handle"], 1, member["revision"], None, member["revision"], None))
                check(f"{label}: member {member['handle']} is reported Created, then Conflicted",
                      [event["kind"] for event in case["expect"].get("events", []) if event.get("handle") == member["handle"]],
                      ["Created", "Conflicted"])
    # An Abandon (SYNC.md section 7) gives up a delivered create of the run's
    # source and nothing else: its binding leaves, the item is marked deleted
    # and, no binding of it left, retained holding what it held, nothing is
    # pushed, and the run reports the provisional handle. On any other
    # placement it is refused, the rows as they were. No other run reports
    # that event.
    if mutation.get("kind") == "Abandon":
        item = next((i for i in store.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
        binding = next((b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                        and b["link_id"] == item.get("link_id") and b["source"] == run["source"]), {})
        if not (binding.get("handle", "").startswith("\u0001") and binding.get("base_present", 0) == 1):
            require(f"{label}: an Abandon on anything but a delivered create fails", case["expect"].get("failed") is True)
            for table in ("items", "bindings"):
                check(f"{label}: a refused Abandon leaves the {table} as they were", after.get(table, store.get(table)), store.get(table))
        else:
            require(f"{label}: an Abandon of a delivered create does not fail", case["expect"].get("failed") is not True)
            check(f"{label}: an Abandon pushes nothing", case["expect"].get("pushes"), [])
            check(f"{label}: an Abandon reports the provisional handle it gave up", case["expect"].get("events"),
                  [{"kind": "Abandoned", "handle": binding["handle"]}])
            require(f"{label}: an Abandon states the rows it leaves", "items" in after and "bindings" in after)
            left = [b for b in after.get("bindings", []) if b["collection"] == run["collection"] and b["link_id"] == item["link_id"]]
            rule_cases["an abandon beside another source"] += bool(left)
            require(f"{label}: an Abandon drops the create's binding", all(b["source"] != run["source"] for b in left))
            # Another source binding the item keeps its binding as it was, and
            # so owes the delete (SYNC.md sections 7 and 9).
            before = [b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                      and b["link_id"] == item["link_id"] and b["source"] != run["source"]]
            check(f"{label}: an Abandon leaves every other source's binding of the item as it was", left, before)
            given = next((i for i in after.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
            require(f"{label}: an Abandon marks the item deleted, retained once no source binds it",
                    given.get("deleted") == 1 and (given.get("retained") is True) == (not left)
                    and (left or given.get("retained_by") == run["source"]))
            check(f"{label}: an abandoned item keeps its body and the flags staged on it",
                  (given.get("object"), given.get("flags")), (item.get("object"), item.get("flags")))
    else:
        require(f"{label}: only an Abandon reports Abandoned",
                all(event.get("kind") != "Abandoned" for event in case["expect"].get("events", [])))
    # The agreement of STORAGE.md section 9 across collections (SYNC.md
    # section 6). A member a page names under a bare key another mail
    # collection holds shares the lowest seq of the rows there it agrees
    # with, on subject, date and sender, and draws one no row held when it
    # agrees with none.
    mail = {c["id"] for c in declared if c["kind"] == "message/rfc822"}
    every_row = {(s["collection"], s["link_id"]): s["row"] for s in store.get("summaries", []) if s["table"] == "mail_summary"}

    def agrees(columns, row):
        return all(columns[column] == row.get(column, columns[column]) for column in ("subject", "date", "sender"))

    if run.get("verb") == "sync" and run["collection"] in mail and "items" in after and not files:
        before = {i["link_id"] for i in store.get("items", []) if i["collection"] == run["collection"]}
        for page in pages:
            for member in page["items"]:
                meta = member.get("meta") or {}
                if not (root / meta.get("body", "")).is_file() or not meta["body"].endswith(".eml"):
                    continue
                columns = mail_columns((root / meta["body"]).read_bytes())
                key = columns["message_id"]
                named = after_items.get((run["collection"], key))
                if key is None or key in before or named is None or key.startswith(RESERVED_PREFIXES):
                    continue
                if not any(b["handle"] == member["handle"] and b["link_id"] == key and b["source"] == run["source"] for b in after.get("bindings", [])):
                    continue
                holders = [(i, every_row[(i["collection"], key)]) for i in store.get("items", [])
                           if i["collection"] in mail and i["collection"] != run["collection"] and i["link_id"] == key
                           and (i["collection"], key) in every_row]
                if not holders:
                    continue
                shared = [i["seq"] for i, row in holders if agrees(columns, row)]
                if shared:
                    check(f"{label}: member {member['handle']} shares the seq of the row it agrees with in another collection", named["seq"], min(shared))
                else:
                    require(f"{label}: member {member['handle']}, disagreeing with every row holding {key} elsewhere, draws a seq of its own",
                            named["seq"] not in {i["seq"] for i in store.get("items", [])})
    # An upgrade leaves no mail placement holding a body its summary disagreed
    # with: a body is linked only from a row that agrees, else fetched.
    bodies = fixtures_of | {object_label: spec["body"] for object_label, spec in expected.get("objects", {}).items()}
    if run.get("verb") == "upgrade" and run["collection"] in mail:
        for handle in run.get("handles", []):
            bound = next((b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                          and b["source"] == run["source"] and b["handle"] == handle), None)
            row = every_row.get((run["collection"], bound["link_id"])) if bound else None
            held_item = after_items.get((run["collection"], bound["link_id"]), {}) if bound else {}
            was = next((i for i in store.get("items", []) if bound and i["collection"] == run["collection"] and i["link_id"] == bound["link_id"]), {})
            if row is None or held_item.get("object") is None or was.get("object") is not None or held_item["object"] not in bodies:
                continue
            columns = mail_columns((root / bodies[held_item["object"]]).read_bytes())
            require(f"{label}: upgraded {handle} holds a body agreeing with the summary it was named by, never another message's linked on its key",
                    agrees(columns, row))
    # A bodiless mail row losing its last binding is purged for a live row of
    # another collection of its account that agrees with it, and retained
    # when every holder states another message (STORAGE.md section 11.1).
    accounts = {c["id"]: c.get("account") for c in declared}
    if "items" in after and "bindings" in after and run["collection"] in mail:
        for item in store.get("items", []):
            key = (item["collection"], item["link_id"])
            if item["collection"] != run["collection"] or item.get("object") is not None or item.get("deleted") == 1 or key not in every_row:
                continue
            if not any((b["collection"], b["link_id"]) == key for b in store.get("bindings", [])) \
                    or any((b["collection"], b["link_id"]) == key for b in after["bindings"]):
                continue
            holders = [every_row[(i["collection"], i["link_id"])] for i in store.get("items", [])
                       if i["collection"] in mail and i["collection"] != item["collection"] and i["link_id"] == item["link_id"]
                       and accounts.get(i["collection"]) == accounts.get(item["collection"]) and i.get("deleted") == 0
                       and (i["collection"], i["link_id"]) in every_row
                       and after_items.get((i["collection"], i["link_id"]), i).get("deleted") == 0]
            if not holders:
                continue
            mine = every_row[key]
            own = {column: mine.get(column) for column in ("subject", "date", "sender")}
            if any(all(column not in row or row[column] == own[column] for column in own) for row in holders):
                require(f"{label}: bodiless {item['link_id']}, held elsewhere by a row that agrees, is purged", key not in after_items)
            else:
                require(f"{label}: bodiless {item['link_id']}, held elsewhere only by another message, is retained, never purged",
                        after_items.get(key, {}).get("retained") is True)
    # The same rule read from its other end: a bodiless mail row the store
    # held and the run leaves no row of was purged as held elsewhere, so a
    # live row of another mail collection of its account holds its key under
    # a stated summary agreeing with its own, the store's or the one its
    # member's meta gives. A holder stating no summary agrees with no message
    # (STORAGE.md sections 9 and 11.1), so a case purging for one states it.
    if "items" in after and run["collection"] in mail and not files:
        metas = {}
        for page in pages:
            for member in page["items"]:
                fixture = (member.get("meta") or {}).get("body", "")
                if fixture.endswith(".eml") and (root / fixture).is_file():
                    metas[member["handle"]] = mail_columns((root / fixture).read_bytes())
        for item in store.get("items", []):
            key = (item["collection"], item["link_id"])
            if item["collection"] != run["collection"] or item.get("object") is not None or key in after_items:
                continue
            own = every_row.get(key) or next((metas[b["handle"]] for b in store.get("bindings", [])
                                              if (b["collection"], b["link_id"]) == key and b["handle"] in metas), None)
            holders = [every_row.get((i["collection"], i["link_id"])) for i in store.get("items", [])
                       if i["collection"] in mail and i["collection"] != item["collection"] and i["link_id"] == item["link_id"]
                       and accounts.get(i["collection"]) == accounts.get(item["collection"]) and i.get("deleted") == 0
                       and after_items.get((i["collection"], i["link_id"]), i).get("deleted") == 0]
            require(f"{label}: bodiless {item['link_id']}, purged, is held elsewhere by a live row stating a summary that agrees with its own",
                    any(row is not None and (own is None or all(row.get(column) == own.get(column) for column in ("subject", "date", "sender")))
                        for row in holders))
    # A member minted apart from a pending or a delivered create of the run's
    # source holding its hint, their summaries disagreeing, is reported
    # Disagreed, naming that create (SYNC.md sections 5 and 6), and no other
    # member is.
    if run.get("verb") == "sync" and not files:
        creates = {b["link_id"] for b in store.get("bindings", []) if b["collection"] == run["collection"]
                   and b["source"] == run["source"] and b["handle"].startswith("\u0001")}
        known = {b["handle"] for b in store.get("bindings", []) if b["collection"] == run["collection"] and b["source"] == run["source"]}
        disagreed = []
        for page in pages:
            for member in page["items"]:
                meta = member.get("meta") or {}
                if member["handle"] in known or not (root / meta.get("body", "")).is_file() or not meta["body"].endswith(".eml"):
                    continue
                columns = mail_columns((root / meta["body"]).read_bytes())
                hint = columns["message_id"]
                for key in (hint, f"dup:{hint}#\u0001{hint}"):
                    row = every_row.get((run["collection"], key))
                    if key in creates and row is not None:
                        if not agrees(columns, row) and {"kind": "Disagreed", "handle": member["handle"], "link_id": key} not in disagreed:
                            disagreed.append({"kind": "Disagreed", "handle": member["handle"], "link_id": key})
                        break
        if not case["expect"].get("failed"):
            check(f"{label}: the Disagreed events", [event for event in case["expect"].get("events", []) if event.get("kind") == "Disagreed"], disagreed)
    # A bodiless Copy or Move needs its source to sync the target (SYNC.md
    # section 7).
    if mutation.get("kind") in ("Copy", "Move"):
        item = next((i for i in store.get("items", []) if i["collection"] == run["collection"] and i["seq"] == mutation["seq"]), {})
        binding = next((b for b in store.get("bindings", []) if b["collection"] == run["collection"]
                        and b["link_id"] == item.get("link_id") and b["source"] == run["source"]), {})
        syncs = any(row["collection"] == mutation["to"] and row["source"] == run["source"]
                    for row in store.get("bindings", []) + store.get("sources", []))
        if item.get("object") is None and not (binding.get("base_present") == 1 and syncs):
            require(f"{label}: a {mutation['kind']} no body nor origin could deliver fails", case["expect"].get("failed") is True)
            for table in ("items", "bindings"):
                check(f"{label}: a refused {mutation['kind']} leaves the {table} as they were", after.get(table, store.get(table)), store.get(table))
    for push in case["expect"].get("pushes", []):
        require(f"{label}: push {push.get('handle')} names a kind", push.get("kind") in {"Add", "Remove", "SetFlags", "Update"})
        require(f"{label}: push {push.get('handle')} carries a key", "key" in push)
        resolved = dict(push)
        if resolved.get("object") is not None:
            require(f"{label}: push {push['handle']} names a known object", push["object"] in names)
            resolved["object"] = names.get(push["object"], push["object"])
        check(f"{label}: push {push.get('handle')} key", push.get("key"), change_key(case["run"]["collection"], resolved))
    for outcome in case["expect"].get("outcomes", []):
        require(f"{label}: outcome {outcome.get('handle')} is Accepted, Rejected or Refused", outcome.get("outcome") in {"Accepted", "Rejected", "Refused"})
        # A connector states whether an accepted Remove carrying `to` relocated
        # the member or deleted it (SYNC.md section 4): only a relocation
        # delivers the destination's create.
        relocating = any(push.get("kind") == "Remove" and push.get("to") is not None and push.get("handle") == outcome.get("handle")
                         for push in case["expect"].get("pushes", []))
        if outcome.get("outcome") == "Accepted" and relocating:
            require(f"{label}: outcome {outcome.get('handle')} states whether it relocated", isinstance(outcome.get("relocated"), bool))
        # An add accepted with no handle (SYNC.md section 4) names no member:
        # its create stays pending under the provisional handle until a page
        # lands it.
        if outcome.get("outcome") == "Accepted" and "assigned" in outcome and outcome["assigned"] is None and outcome.get("handle", "").startswith("\u0001"):
            require(f"{label}: an add accepted without a handle keeps its provisional binding",
                    any(binding["handle"] == outcome["handle"] for binding in case["expect"].get("store", {}).get("bindings", [])))
    # A refused change is held (SYNC.md section 5): no push carries the key a
    # refusal standing on its binding names; a Refused outcome stands on the
    # binding it was pushed for, under that push's key, and is reported with
    # its reason, as a held one is; an accepted push of a refused binding
    # clears its refusal. A create the source binds not, one the store
    # offered, is bound by that write as its pending create, so its refusal
    # stands on a binding too.
    before_own, after_own = ({b["handle"]: b for b in rows.get("bindings", [])
                              if b["collection"] == run["collection"] and b["source"] == run["source"]}
                             for rows in (store, after))
    standing = {handle: b for handle, b in before_own.items() if b.get("refusal") is not None}
    for binding in list(before_own.values()) + list(after_own.values()):
        require(f"{label}: binding {binding['handle']} states a refusal with its key, or neither",
                (binding.get("refusal") is None) == (binding.get("refused_key") is None))
    keys = {push["handle"]: push.get("key") for push in case["expect"].get("pushes", [])}
    reported = {(event["handle"], event.get("reason")) for event in case["expect"].get("events", []) if event["kind"] == "Refused"}
    for handle, key in keys.items():
        require(f"{label}: push {handle} carries no key a refusal standing on its binding names",
                handle not in standing or standing[handle].get("refused_key") != key)
    refused_now = set()
    for outcome in case["expect"].get("outcomes", []):
        handle = outcome["handle"]
        if outcome["outcome"] == "Refused":
            refused_now.add(handle)
            require(f"{label}: refusal of {handle} is reported with its reason", (handle, outcome.get("reason")) in reported)
            if "bindings" in after:
                binding = after_own.get(handle, {})
                if handle not in before_own:
                    require(f"{label}: the offered create {handle} is bound as a pending create on its refusal",
                            handle in after_own and after_own[handle].get("base_present") == 0)
                    rule_cases["an offered create bound on its refusal"] += 1
                require(f"{label}: refusal of {handle} stands on its binding under the key pushed",
                        binding.get("refusal") == outcome.get("reason") and binding.get("refused_key") == keys.get(handle))
            rule_cases["a refusal recorded"] += 1
        if outcome["outcome"] == "Accepted" and handle in standing and handle in after_own:
            require(f"{label}: an accepted push of {handle} clears its refusal",
                    "refusal" in after_own[handle] and after_own[handle]["refusal"] is None)
            rule_cases["a refusal cleared by an accepted push"] += 1
    for handle, reason in reported:
        require(f"{label}: a Refused event names a refusal of the run or one standing",
                handle in refused_now or (handle in standing and standing[handle]["refusal"] == reason))
        if handle in standing and handle not in keys:
            rule_cases["a refused change held"] += 1
            if "bindings" in after:
                require(f"{label}: a held refusal of {handle} still stands",
                        after_own.get(handle, {}).get("refused_key") == standing[handle]["refused_key"])
for rule, count in rule_cases.items():
    require(f"sync: a case holds {rule}", count >= 1)

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
# The digits a relative amount and a stamp hold at most, read from the
# grammar's two rules.
DIGITS = {rule: int(most) for rule, most in re.findall(r"^(relative|stamp) += 1\*(\d+)DIGIT\b", search_md, re.M)}
check("search grammar: relative and stamp bound their digits", sorted(DIGITS), ["relative", "stamp"])
DIGITS = {"relative": 0, "stamp": 0} | DIGITS
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

# A seq is one item's (STORAGE section 9.1): the placements sharing one hold
# one link id and one body. An item stated unreadable has its blob taken out
# before the index is built (SEARCH.md section 11), so no other item may hold
# that body, which would go with it.
by_seq = {}
for item in store["items"]:
    by_seq.setdefault(item["seq"], []).append(item)
for seq, placed in by_seq.items():
    require(f"search store: seq {seq} names one item, one link id and one body in every collection filing it",
            len({(item["link_id"], item.get("fixture"), item.get("unreadable", False)) for item in placed}) == 1
            and (len(placed) == 1 or all("fixture" in item for item in placed))
            and len({item["collection"] for item in placed}) == len(placed))
unreadable = {item["fixture"] for item in store["items"] if item.get("unreadable")}
for item in store["items"]:
    if item.get("fixture") in unreadable:
        require(f"search store: {item['fixture']} is unreadable for every item holding it", item.get("unreadable") is True)
require("search store: an item's body cannot be read", len(unreadable) >= 1)

# A reference names two endpoints the store holds (STORAGE section 14.2), each
# a kind and a link id with an item under that kind.
kinds = {c["id"]: c["kind"] for c in store["collections"]}
endpoints = {(kinds[item["collection"]], item["link_id"]) for item in store["items"]}
for reference in store.get("references", []):
    for end in ("from", "to"):
        endpoint = (reference[f"{end}_kind"], reference[f"{end}_link_id"])
        require(f"search store: reference {end} {endpoint} is held", endpoint in endpoints)

# A case's now and zone (SEARCH.md section 11), the file's now and UTC by
# default.
def clock_of(case):
    label = f"search {case['query']!r}"
    now = case.get("now", queries["now"])
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", now) is None:
        failures.append(f"{label}: now {now!r} is no UTC instant")
        now = queries["now"]
    try:
        zone = ZoneInfo(case["zone"]) if "zone" in case else timezone.utc
    except (ZoneInfoNotFoundError, ValueError):
        failures.append(f"{label}: zone {case['zone']!r} names no IANA zone")
        zone = timezone.utc
    return instant(now), zone


# A case answers hits, a threaded listing or a refusal (SEARCH.md section 11),
# and the grammar above accepts its query or refuses it as the case says.
KEYS = {"query", "hits", "threads", "error", "sort", "ordered", "horizon_left", "temporal", "cut", "zone", "now", "note",
        "index_zone", "zone_differs", "coverage", "complete"}
for case in queries["cases"]:
    label = f"search {case['query']!r}"
    require(f"{label}: known keys only", set(case) <= KEYS)
    require(f"{label}: no date point of the year 0000, which point_span cannot place",
            not re.search(r"\b(date|when):\"?(\S*\.\.)?0000", case["query"]))
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
    now, zone = clock_of(case)
    left = None if "error" in case else horizon_left_of(case["query"], store["collections"], now, queries["horizon"], zone)
    if left is not None:
        check(f"{label}: horizon_left", case.get("horizon_left", False), left)
    try:
        parse(case["query"])
        got = None
    except Refused as refused:
        got = {"code": refused.code, "start": refused.start, "end": refused.end}
    if "error" in case:
        require(f"{label}: refusals carry no sort, order, coverage or clock",
                not set(case) & {"sort", "ordered", "horizon_left", "temporal", "cut", "zone", "now", "index_zone", "zone_differs", "coverage", "complete"})
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
    """One FTS5 string, its `"` doubled and its U+0000 a space, a prefix
    starred, filtered to a column (SEARCH.md section 8.5)."""
    expression = '"' + fold(text).replace('"', '""').replace("\x00", " ") + '"' + (" *" if prefix else "")
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
    # A hit is (account, seq), one for an item filed twice in an account.
    return [list(hit) for hit in sorted({(accounts[titled[at - 1][1]["collection"]], titled[at - 1][1]["seq"]) for at, in rows})]


FTS5_SYNTAX = re.compile(r'[\^+{}():*"-]|\b(AND|OR|NOT|NEAR)\b')
title_cases = nul_cases = 0
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
    if "\x00" in text:
        # FTS5 reads no expression past U+0000: left in the string, the
        # term must be one FTS5 refuses or answers otherwise.
        nul_cases += 1
        try:
            kept = title_hits('{title} : "' + fold(text).replace('"', '""') + '"')
        except sqlite3.OperationalError:
            kept = None
        require(f"{label}: holds U+0000 that its text left in the FTS5 string answers alike", kept != sorted(case["hits"]))
require("search: a text term holding FTS5 syntax is re-derived", title_cases >= 9)
require("search: a text term holding U+0000 is re-derived", nul_cases >= 1)

# The bounds of SEARCH.md section 7, read from its prose, and a second path
# expanding a series a simple rule states: one VEVENT, a UTC DTSTART, a
# DURATION, an RRULE stepping by the second, the minute, the hour or the day
# whose BYxxx parts only limit, no COUNT, UNTIL, RDATE, EXDATE nor override;
# or one whose BYxxx parts only expand each period into the same instants,
# with a COUNT or none. Its occurrences in the windows, and the cut a case
# reaching it counts, follow the bounds; every other calendar item of the
# store states a bounded series and is never cut.
bounds = re.search(r"An item writes at most ([\d,]+) occurrences.*?examines at most ([\d,]+) periods"
                   r".*?walks at most ([\d,]+) instances", search_md)
OCCURRENCES, PERIODS, INSTANCES = (int(number.replace(",", "")) for number in bounds.groups())
# The BYxxx parts that expand a period of each step into its instants.
EXPANDING = {"MINUTELY": {"BYSECOND"}, "HOURLY": {"BYMINUTE", "BYSECOND"}}
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
    length = int(duration[1][2:-1]) * {"H": 3600, "M": 60, "S": 1}[duration[1][-1]]
    first = epoch(f"{start[1][0:4]}-{start[1][4:6]}-{start[1][6:8]}T{start[1][9:11]}:{start[1][11:13]}:{start[1][13:15]}Z")
    if step and set(rule) & EXPANDING.get(frequency, set()):
        return expanded_series(rule, frequency, step, first, length, horizon)
    if not step or set(rule) - LIMITING[frequency]:
        return None
    sets = {part: {int(value) for value in values.split(",")} for part, values in rule.items()}
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


def expanded_series(rule, frequency, step, first, length, horizon):
    """The occurrences and the cut of a rule whose BYxxx parts only expand
    each period into the same instants, a COUNT or none beside them: the
    instances counted from DTSTART by arithmetic, under the three bounds of
    section 7. None for a rule holding another part."""
    count = int(rule.pop("COUNT")) if "COUNT" in rule else None
    if set(rule) - EXPANDING[frequency]:
        return None
    sets = {part: sorted({int(value) for value in values.split(",")}) for part, values in rule.items()}
    unit = STEPS[frequency]
    origin = first - first % unit
    seconds = sets.get("BYSECOND", [first % 60])
    minutes = sets.get("BYMINUTE", [first % 3600 // 60]) if frequency == "HOURLY" else [0]
    offsets = sorted(minute * 60 + second for minute in minutes for second in seconds)
    head = [offset for offset in offsets if origin + offset >= first]

    def start_of(n):
        if n < len(head):
            return origin + head[n]
        period, at = divmod(n - len(head), len(offsets))
        return origin + (period + 1) * step + offsets[at]

    in_periods = len(head) + (PERIODS - 1) * len(offsets)
    walked = min(INSTANCES, in_periods, count if count is not None else INSTANCES)
    cut = None
    if count is None or count > walked:
        cut = start_of(INSTANCES) if INSTANCES <= in_periods else origin + PERIODS * step

    low, high = horizon
    begin, end = 0, walked
    while begin < end:
        middle = (begin + end) // 2
        if start_of(middle) + length > low:
            end = middle
        else:
            begin = middle
            begin += 1
    written = []
    for n in range(begin, walked):
        at = start_of(n)
        if at >= high:
            break
        if len(written) == OCCURRENCES:
            cut = at if cut is None else min(cut, at)
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


def cut_of(query, collections, now, zone=timezone.utc):
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
            end = point_span(value, now, zone)[1]
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
        derived = cut_of(case["query"], store["collections"], *clock_of(case))
        require(f"{label}: a cut case is one checks/vectors.py re-derives", derived is not None)
        check(f"{label}: cut", case["cut"], derived)


# The hits of a case stating a zone (SEARCH.md sections 7, 8.1), over single
# events placed as an index stating that zone places them.
def single_event(bytes_, zone):
    found = [c for c in components(bytes_)[2][0][2] if c[0] in ("VEVENT", "VTODO", "VJOURNAL", "VTIMEZONE")]
    if len(found) != 1 or found[0][0] != "VEVENT":
        return None
    properties = {prop: (params, value) for prop, params, value in found[0][1]}
    if {"RRULE", "RDATE", "RECURRENCE-ID", "DURATION"} & set(properties) or "DTSTART" not in properties:
        return None

    def at(params, value):
        if re.fullmatch(r"\d{8}", value):
            day = date(int(value[0:4]), int(value[4:6]), int(value[6:8]))
            return datetime(day.year, day.month, day.day, tzinfo=zone).astimezone(timezone.utc), day
        wall = datetime.strptime(value.removesuffix("Z"), "%Y%m%dT%H%M%S")
        if value.endswith("Z"):
            return wall.replace(tzinfo=timezone.utc), None
        tzid = params.get("TZID")
        return wall.replace(tzinfo=ZoneInfo(tzid) if tzid else zone, fold=0).astimezone(timezone.utc), None

    start, day = at(*properties["DTSTART"])
    if "DTEND" in properties:
        end = at(*properties["DTEND"])[0]
    elif day is not None:
        after = day + timedelta(days=1)
        end = datetime(after.year, after.month, after.day, tzinfo=zone).astimezone(timezone.utc)
    else:
        end = start
    return start, end


MEDIA = {"mail": "message/rfc822", "contact": "text/vcard", "event": "text/calendar", "task": "text/calendar",
         "journal": "text/calendar", "file": "application/octet-stream"}


def conjuncts_of(query):
    """A query's terms with whether each stands as a conjunct of the whole
    query (SEARCH.md section 8.2), or None for a query holding an `or`,
    which this does not read. A term right after a `not` or a `-` is none,
    nor is one inside a negated group; a group that is itself a conjunct is
    read through, its terms standing as the query's own."""
    tokens = lex(query)
    if any(token["kind"] == "operator" and token["word"] == "or" for token in tokens):
        return None
    terms, negated, groups = [], False, []
    for token in tokens:
        if token["kind"] == "operator":
            negated = negated or token["word"] == "not"
        elif token["kind"] == "(":
            groups.append(negated or (bool(groups) and groups[-1]))
            negated = False
        elif token["kind"] == ")":
            groups.pop()
            negated = False
        else:
            terms.append((token, not negated and not (groups and groups[-1])))
            negated = False
    return terms


def field_of(query, token):
    """A field term's name and value, a phrase value without its quotes."""
    name = query[token["start"]:token["colon"]]
    value = query[token["colon"] + 1:token["end"]]
    return name, value[1:-1] if token["phrase"] else value


def collections_of(query):
    """The query's collections (SEARCH.md section 8.2): those its account:,
    collection:, folder: and kind: conjuncts leave."""
    terms = conjuncts_of(query)
    if terms is None:
        return None
    scope = list(store["collections"])
    for token, conjunct in terms:
        if token["kind"] != "field" or not conjunct:
            continue
        name, value = field_of(query, token)
        if name in ("collection", "folder"):
            scope = [c for c in scope if c["id"] == value]
        elif name == "account":
            scope = [c for c in scope if c["account"] == value]
        elif name == "kind":
            scope = [c for c in scope if c["kind"] == MEDIA[value]]
    return scope


def dated_of(query):
    """The value of the query's date: or when: conjunct, None with none, and
    False for a query whose date terms this does not read: more than one, or
    one that is no conjunct."""
    found = [(field_of(query, token)[1], conjunct) for token, conjunct in conjuncts_of(query)
             if token["kind"] == "field" and field_of(query, token)[0] in DATE_FIELDS]
    if not found:
        return None
    return found[0][0] if len(found) == 1 and found[0][1] else False


def range_span(value, now, zone):
    """A date value's span, either side None when open."""
    low, _, high = value.partition("..") if ".." in value else (value, "", value)
    return (point_span(low, now, zone)[0] if low else None), (point_span(high, now, zone)[1] if high else None)


def sealed(bytes_):
    """Whether a message's body is one the extraction records encrypted
    (SEARCH.md section 6), by its own Content-Type."""
    stated = header_field(header_fields(bytes_), "content-type") or ""
    return stated.strip().lower().split(";")[0].strip() in ("multipart/encrypted", "application/pkcs7-mime")


def coverage_of(scope):
    """What `coverage` answers over collections (SEARCH.md section 8.2), per
    kind: the bodiless items, the placements stated unreadable, none recorded
    unparseable, every fixture being one its parser accepts, and the
    placements of an encrypted message; a file never, a kind counting nothing
    left out."""
    ids = {c["id"]: c["kind"] for c in scope if c["kind"] != "application/octet-stream"}
    counts = {}
    for item in store["items"]:
        kind = ids.get(item["collection"])
        if kind is None:
            continue
        row = counts.setdefault(kind, {"bodiless": 0, "missing": 0, "unparseable": 0, "encrypted": 0})
        if "summary" in item:
            row["bodiless"] += 1
        elif item.get("unreadable"):
            row["missing"] += 1
        elif kind == "message/rfc822" and sealed((root / item["fixture"]).read_bytes()):
            row["encrypted"] += 1
    return {kind: row for kind, row in counts.items() if any(row.values())}


# The kinds whose bodies a term reads (SEARCH.md section 8.2), and the text
# terms matched in the body or the attachment field (section 8.5).
EVERY_BODY = {"message/rfc822", "text/vcard", "text/calendar"}
CARD_MARKS = {"phone", "address", "birthday", "photo"}


def reads_of(query):
    """The kinds whose bodies the query's terms read, wherever they stand,
    whether a text term of it reaches the body or the attachment field, and
    whether it asks a message's attachment mark."""
    kinds, reaches, marks = set(), False, False
    for token in lex(query):
        if token["kind"] in ("text", "phrase"):
            kinds |= EVERY_BODY
            reaches = True
        elif token["kind"] == "field":
            name, value = field_of(query, token)
            if name in TEXT_FIELDS and not (name in ADDRESS_FIELDS and "@" in value):
                kinds |= EVERY_BODY
                reaches = reaches or name in ("body", "attachment", "mimetype")
            elif name in DATE_FIELDS:
                kinds.add("text/calendar")
            elif name == "has" and value == "attachment":
                kinds.add("text/calendar")
                marks = True
            elif name == "thread":
                kinds.add("message/rfc822")
            elif (name == "has" and value in CARD_MARKS) or name == "category":
                kinds.add("text/vcard")
            elif name == "is" and value == "encrypted":
                kinds.add("message/rfc822")
    return kinds, reaches, marks


def rfc3339(moment):
    return None if moment is None else moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def complete_of(query, now, zone):
    """Whether an answer is complete (SEARCH.md section 8.2), on an index
    that folded every change: the temporal axis full, no range out of the
    horizon, no item cut before its end, no bodiless item, missing or
    unparseable placement of a kind a term reads, no bodiless message under
    has:attachment, no encrypted body under a text term reaching one. None
    for a query this does not read."""
    scope = collections_of(query)
    if scope is None or dated_of(query) is False:
        return None
    since = until = None
    calendar = any(c["kind"] == "text/calendar" for c in scope)
    if dated_of(query) is not None:
        since, until = range_span(dated_of(query), now, zone)
        if calendar:
            if since is None or until is None or since < horizon[0] or until > horizon[1]:
                return False
            ids = {c["id"] for c in scope}
            if any(collection in ids and cut is not None and instant(cut) < until for (collection, _), (_, cut) in series.items()):
                return False
    if rollup(scope, rfc3339(since), rfc3339(until)) != "full":
        return False
    kinds, reaches, marks = reads_of(query)
    for kind, row in coverage_of(scope).items():
        if kind in kinds and (row["bodiless"] or row["missing"] or row["unparseable"]):
            return False
        if (marks and kind == "message/rfc822" and row["bodiless"]) or (reaches and row["encrypted"]):
            return False
    return True


check("search coverage: the file's, over every collection of the store", queries["coverage"], coverage_of(store["collections"]))
stated = {"coverage": 0, "complete": 0, True: 0, False: 0, "sealed": set(), "lost": set()}
for case in queries["cases"]:
    if "error" in case:
        continue
    label = f"search {case['query']!r}"
    now, zone = clock_of(case)
    scope = collections_of(case["query"])
    if "coverage" in case:
        require(f"{label}: a coverage case is one checks/vectors.py re-derives", scope is not None)
        if scope is not None:
            check(f"{label}: coverage over the query's collections", case["coverage"], coverage_of(scope))
            stated["coverage"] += 1
    if "complete" in case:
        derived = complete_of(case["query"], now, zone)
        require(f"{label}: a complete case is one checks/vectors.py re-derives", derived is not None)
        if derived is not None:
            check(f"{label}: complete", case["complete"], derived)
            stated["complete"] += 1
            stated[derived] += 1
            counts = coverage_of(scope).get("message/rfc822", {})
            for key, count in (("sealed", "encrypted"), ("lost", "missing")):
                if counts.get(count) and not counts.get("bodiless"):
                    stated[key].add(derived)
    # The zone the query states against the one the index read floating times
    # in (SEARCH.md sections 8.1, 8.2), compared as names, said only where a
    # date term can reach a calendar item.
    index_zone = case.get("index_zone", case.get("zone", "UTC"))
    if scope is None or dated_of(case["query"]) is False:
        require(f"{label}: a case stating zone_differs or index_zone is one checks/vectors.py re-derives",
                not set(case) & {"zone_differs", "index_zone"})
    else:
        differs = (index_zone != case.get("zone", "UTC") and dated_of(case["query"]) is not None
                   and any(c["kind"] == "text/calendar" for c in scope))
        check(f"{label}: zone_differs", case.get("zone_differs", False), differs)
        stated["differs" if differs else "agrees"] = stated.get("differs" if differs else "agrees", 0) + ("index_zone" in case)
require("search: cases state the coverage of their collections and whether they are complete, either way",
        stated["coverage"] >= 4 and stated[True] >= 3 and stated[False] >= 3)
require("search: a collection holding an encrypted body and none bodiless answers complete and not, by the query's terms",
        stated["sealed"] == {True, False})
require("search: a collection holding a missing body and none bodiless answers complete and not, by the query's terms",
        stated["lost"] == {True, False})
require("search: a case asks in another zone than its index's, with and without a calendar in reach",
        stated.get("differs", 0) >= 1 and stated.get("agrees", 0) >= 1)


# The hits of a case asking mail alone by date, `kind:mail` beside one date
# term (SEARCH.md section 8.1): a message compares its sort key, its date
# (STORAGE Annex A.1), which no zone places, against the term's span, a side
# no instant of a four-digit year states being open.
mail_dated = 0
for case in queries["cases"]:
    terms = case["query"].split()
    if "hits" not in case or len(terms) != 2 or terms[0] != "kind:mail" or not terms[1].startswith("date:"):
        continue
    since, until = range_span(terms[1][5:], *clock_of(case))
    derived = set()
    for item in store["items"]:
        if kinds[item["collection"]] != "message/rfc822":
            continue
        key = instant(item["summary"]["sort_key"] if "summary" in item else mail_columns((root / item["fixture"]).read_bytes())["date"])
        if (since is None or since <= key) and (until is None or key < until):
            derived.add((accounts[item["collection"]], item["seq"]))
    check(f"search {case['query']!r}: the messages dated in the range", sorted(map(tuple, case["hits"])), sorted(derived))
    mail_dated += since is None or until is None
require("search: a date range open on a side no four-digit year states is re-derived, each side", mail_dated >= 2)

for case in queries["cases"]:
    if "zone" not in case:
        continue
    label = f"search {case['query']!r}"
    terms = dict(term.partition(":")[::2] for term in case["query"].split())
    if not (len(case["query"].split()) == 2 and set(terms) in ({"collection", "date"}, {"kind", "date"})
            and terms.get("kind", "mail") == "mail" and ".." not in terms["date"] and "hits" in case):
        failures.append(f"{label}: a zoned case is one checks/vectors.py re-derives")
        continue
    now, zone = clock_of(case)
    try:
        placed = ZoneInfo(case["index_zone"]) if case.get("index_zone", "UTC") != "UTC" else timezone.utc
    except (ZoneInfoNotFoundError, ValueError):
        failures.append(f"{label}: index_zone {case['index_zone']!r} names no IANA zone")
        continue
    if "index_zone" not in case:
        placed = zone
    if "kind" in terms:
        continue
    since, until = point_span(terms["date"], now, zone)
    derived = set()
    for item in store["items"]:
        if item["collection"] != terms["collection"]:
            continue
        span = single_event((root / item["fixture"]).read_bytes(), placed) if "fixture" in item else None
        if span is None:
            failures.append(f"{label}: {item['link_id']} is no single event this re-derives")
            continue
        start, end = span
        if start < until and (end > since or (start == end and start >= since)):
            derived.add((accounts[item["collection"]], item["seq"]))
    check(f"{label}: hits read in {case['zone']}", sorted(map(tuple, case["hits"])), sorted(derived))


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
    f"{len(versions['cases'])} version orders, "
    f"{len(objects['objects'])} object names, "
    f"{len(summaries['cases'])} summaries over {len(fixtures)} fixtures, "
    f"{sum('hint' in case for case in summaries['cases'])} minted link ids, "
    f"{len(sync_cases)} sync cases, {len(queries['cases'])} search cases, {len(chunk_cases)} chunk cases, "
    f"{len(writers['cases'])} task writer cases, {len(payload_cases)} payloads and {enqueued} scenario payloads check, "
    f"every file the manifest's"
)
