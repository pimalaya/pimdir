#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# States what each canonical statement binds and answers, and holds the
# tracked statement of it, queries/signatures.json, to the statements
# (STORAGE.md §4.4): for every file under queries/, its name, its parameters
# in order of first appearance, the list slots it reads, and the columns it
# answers, in order, as SQLite names them once the statement is prepared
# against the canonical schemas. A change to a statement that moves none of
# the three is a change of text alone; one that moves any shows in the diff of
# the file. Every answered column carries a name of its own, a lowercase
# identifier, never the text of the expression answering it.
#
#     python3 checks/signatures.py .             compares, failing on a drift
#     python3 checks/signatures.py . --write     prints the file's content
#
# Needs python3 alone, its sqlite3 module at an SQLite the search schema
# loads on (SEARCH.md §2).
import json
import re
import sqlite3
import sys
import tempfile
from pathlib import Path

NAME = re.compile(r"[a-z_][a-z0-9_]*")


def bare(text):
    """The text with its comments and its string literals emptied, so a
    colon inside either names no parameter."""
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r"'(?:[^']|'')*'", "''", text)


def first_seen(found):
    seen = []
    for name in found:
        if name not in seen:
            seen.append(name)
    return seen


def split(text):
    """The statements of a file, one text each."""
    statements, current = [], ""
    for line in text.splitlines(keepends=True):
        current += line
        if sqlite3.complete_statement(current):
            if bare(current).strip():
                statements.append(current)
            current = ""
    if bare(current).strip():
        statements.append(current)
    return statements


def returning(statement):
    """A write's RETURNING list read as a SELECT over the table it writes,
    so its columns are named without running the write."""
    code = bare(statement)
    at = [m.start() for m in re.finditer(r"\bRETURNING\b", code)]
    table = re.match(r"\s*(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+([a-z_.]+)", code, re.I)
    if not at or not table:
        return None
    # Offsets hold in the original text only up to the first literal, so the
    # list is cut from the text itself at the last RETURNING outside one.
    last = [m.start() for m in re.finditer(r"\bRETURNING\b", statement)][-1]
    return f"SELECT {statement[last + len('RETURNING'):].strip().rstrip(';')} FROM {table.group(1)} LIMIT 0"


def columns(connection, statement):
    parameters = {name: None for name in re.findall(r":([a-z_][a-z0-9_]*)", bare(statement))}
    head = bare(statement).lstrip().split(None, 1)[0].upper()
    if head not in ("SELECT", "WITH"):
        statement = returning(statement)
        if statement is None:
            return []
    cursor = connection.cursor()
    try:
        cursor.execute(statement, parameters)
    except sqlite3.Error:
        # A parameter SQLite refuses as NULL (a LIMIT, a MATCH): bound as
        # text instead, the columns being the same whatever is bound.
        cursor = connection.cursor()
        cursor.execute(statement, {name: "0" for name in parameters})
    return [column[0] for column in cursor.description or []]


def signatures(root):
    with tempfile.TemporaryDirectory() as directory:
        store, index = Path(directory, "pimdir.db"), Path(directory, "index.db")
        for path, part in ((store, "storage"), (index, "search")):
            connection = sqlite3.connect(path)
            for migration in sorted((root / "migrations" / part).glob("*.sql")):
                connection.executescript(migration.read_text())
            connection.close()
        param = (root / "queries/storage/read/create_param.sql").read_text()
        connections = {"storage": sqlite3.connect(store), "search": sqlite3.connect(index)}
        connections["search"].execute("ATTACH ? AS store", (str(store),))
        for connection in connections.values():
            connection.executescript(param)

        entries = []
        for path in sorted((root / "queries").rglob("*.sql")):
            name = path.relative_to(root / "queries").with_suffix("").as_posix()
            text = path.read_text()
            code = bare(text)
            answered = []
            for statement in split(text):
                answered += columns(connections[name.split("/")[0]], statement)
            entries.append({
                "name": name,
                "parameters": first_seen(re.findall(r":([a-z_][a-z0-9_]*)", code)),
                "slots": first_seen(re.findall(r"slot = '([a-z_]*)'", re.sub(r"--[^\n]*", "", text))),
                "columns": answered,
            })
        for connection in connections.values():
            connection.close()
        return entries


def render(entries):
    return "[\n" + ",\n".join(json.dumps(entry, ensure_ascii=False) for entry in entries) + "\n]\n"


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    entries = signatures(root)

    failures = 0
    for entry in entries:
        unnamed = [column for column in entry["columns"] if not NAME.fullmatch(column)]
        twice = sorted({column for column in entry["columns"] if entry["columns"].count(column) > 1})
        if unnamed:
            print(f"{entry['name']}: answers a column with no name of its own: {unnamed}", file=sys.stderr)
            failures += 1
        if twice:
            print(f"{entry['name']}: answers two columns under one name: {twice}", file=sys.stderr)
            failures += 1

    generated = render(entries)
    if "--write" in sys.argv[2:]:
        sys.stdout.write(generated)
        sys.exit(1 if failures else 0)

    tracked = root / "queries/signatures.json"
    if not tracked.exists() or tracked.read_text() != generated:
        print(
            "queries/signatures.json is not what the statements state; restate it with\n"
            "    python3 checks/signatures.py . --write > queries/signatures.json",
            file=sys.stderr,
        )
        if tracked.exists():
            held = {entry["name"]: entry for entry in json.loads(tracked.read_text())}
            stated = {entry["name"]: entry for entry in entries}
            for name in sorted(held.keys() | stated.keys()):
                if held.get(name) != stated.get(name):
                    print(f"  {name}: tracked {held.get(name)}, stated {stated.get(name)}", file=sys.stderr)
        failures += 1
    if failures:
        sys.exit(1)
    print(f"{len(entries)} statements state their parameters, slots and columns as queries/signatures.json holds them, every column named")


main()
