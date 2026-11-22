#!/usr/bin/env python3
# A mechanical map of which table.column every canonical statement reads and
# writes, taken from SQLite's authorizer at prepare time.
#
#     python3 touches.py <pimdir repo> <output directory>
#
# Every statement is prepared (as EXPLAIN, so nothing runs) four times: on the
# full schema and on a copy with every trigger dropped, each with foreign keys
# on and off. The differences say how an access is reached:
#
#   in the trigger-less copy, foreign keys off   direct (top-level SQL)
#   only with foreign keys on                    via_fk (a key check or an
#                                                ON DELETE/UPDATE action)
#   only with the triggers                       via_trigger
#
# The authorizer's last argument names the innermost trigger, view or CTE, so
# a view or a CTE read from inside a trigger body hides the trigger: such a
# row is given the fired triggers whose own body (prepared alone, every other
# trigger dropped) makes the same access.
import collections
import re
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

ACTIONS = {
    sqlite3.SQLITE_READ: "READ",
    sqlite3.SQLITE_UPDATE: "UPDATE",
    sqlite3.SQLITE_INSERT: "INSERT",
    sqlite3.SQLITE_DELETE: "DELETE",
}
SUMMARIES = ["mail_summary", "contact_summary", "event_summary", "task_summary", "journal_summary", "file_summary"]
DECLARED = ["items", "bindings", "sources", "collections", "objects", "queue", "receipts", "store_meta"]


def bare(text):
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r"'(?:[^']|'')*'", "''", text)


def split(text):
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


class Recorder:
    def __init__(self, names):
        self.names = names
        self.rows = set()
        self.on = False

    def __call__(self, action, one, two, database, source):
        if self.on and action in ACTIONS:
            self.rows.add((ACTIONS[action], database, one, two or "", source))
        return sqlite3.SQLITE_OK

    def take(self, lookup):
        rows, self.rows = self.rows, set()
        out = set()
        for action, database, table, column, source in rows:
            if database is None:
                database = lookup.get(table, "?")
            else:
                database = self.names.get(database, database)
            out.add((action, database, table, column, source))
        return out


def catalog(path, label):
    """Tables, columns, indexes, triggers and views of one database file."""
    connection = sqlite3.connect(path)
    tables = {}
    for _, name, kind, ncol, wr, strict in connection.execute("PRAGMA table_list"):
        if name.startswith("sqlite_"):
            continue
        columns = [
            {"cid": c[0], "name": c[1], "type": c[2], "notnull": c[3], "default": c[4], "pk": c[5], "hidden": c[6]}
            for c in connection.execute(f"PRAGMA table_xinfo('{name}')")
        ]
        indexes = []
        for _, index, unique, origin, partial in connection.execute(f"PRAGMA index_list('{name}')"):
            keys = [r[2] if r[2] is not None else "<expr>" for r in connection.execute(f"PRAGMA index_xinfo('{index}')") if r[5]]
            indexes.append({"name": index, "unique": unique, "origin": origin, "partial": partial, "keys": keys})
        sql = connection.execute("SELECT sql FROM sqlite_master WHERE name = ?", (name,)).fetchone()
        tables[name] = {
            "db": label, "name": name, "kind": kind, "wr": wr, "strict": strict,
            "columns": columns, "indexes": indexes, "sql": sql[0] if sql else "", "triggers": [],
        }
    triggers = {}
    head = re.compile(
        r"CREATE\s+TRIGGER\s+(\w+)\s+(BEFORE|AFTER|INSTEAD\s+OF)\s+(INSERT|DELETE|UPDATE)(?:\s+OF\s+([\w\s,]+?))?\s+ON\s+(\w+)",
        re.I,
    )
    for name, table, sql in connection.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'trigger' ORDER BY rowid"):
        m = head.match(bare(sql))
        of = [c.strip() for c in m.group(4).split(",")] if m.group(4) else []
        when = bool(re.search(r"\bWHEN\b", bare(sql).split("BEGIN", 1)[0]))
        triggers[name] = {"name": name, "table": table, "timing": m.group(2).upper(), "event": m.group(3).upper(), "of": of, "when": when, "sql": sql, "db": label}
        tables[table]["triggers"].append(name)
    connection.close()
    return tables, triggers


def drop_triggers(path, keep=()):
    connection = sqlite3.connect(path)
    for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'").fetchall():
        if name not in keep:
            connection.execute(f"DROP TRIGGER {name}")
    connection.commit()
    connection.close()


def open_as(part, store, index, param, foreign_keys):
    """A connection as checks/signatures.py opens it: the store alone for a
    storage statement, the index with the store attached as `store` for a
    search one, temp.param created on it."""
    if part == "storage":
        connection = sqlite3.connect(store, isolation_level=None, cached_statements=0)
        names = {"main": "store", "temp": "temp"}
    else:
        connection = sqlite3.connect(index, isolation_level=None, cached_statements=0)
        connection.execute("ATTACH ? AS store", (str(store),))
        names = {"main": "index", "store": "store", "temp": "temp"}
    connection.execute(f"PRAGMA foreign_keys = {'ON' if foreign_keys else 'OFF'}")
    connection.executescript(param)
    recorder = Recorder(names)
    connection.set_authorizer(recorder)
    return connection, recorder


def prepare(connection, recorder, statement, lookup, explain=True):
    """Prepares one statement under the authorizer and answers what it
    recorded, and the error if SQLite refused it."""
    parameters = {name: None for name in re.findall(r":([a-z_][a-z0-9_]*)", bare(statement))}
    text = ("EXPLAIN " if explain else "") + statement
    error = None
    recorder.on = True
    try:
        try:
            connection.execute(text, parameters).fetchall()
        except sqlite3.Error as first:
            if explain:
                try:
                    connection.execute(text, {name: "0" for name in parameters}).fetchall()
                except sqlite3.Error as second:
                    error = f"{first} / as text: {second}"
            else:
                error = str(first)
    finally:
        recorder.on = False
    return recorder.take(lookup), error


def insert_targets(text):
    """The tables an INSERT of the text names, each with its column list or
    None when it names none (read from the text, not from the authorizer)."""
    found = []
    pattern = re.compile(r"\bINSERT\s+(?:OR\s+\w+\s+)?INTO\s+(?:(\w+)\.)?(\w+)(?:\s+AS\s+\w+)?\s*(?:\(([^()]*)\))?", re.I)
    for m in pattern.finditer(bare(text)):
        listed = m.group(3)
        if listed is not None and re.fullmatch(r"[\w\s,]+", listed):
            found.append((m.group(1), m.group(2), [c.strip() for c in listed.split(",")]))
        else:
            found.append((m.group(1), m.group(2), None))
    return found


def declared(sql):
    """The column definitions and table constraints of a CREATE TABLE text,
    one each, comments dropped, whitespace collapsed."""
    code = re.sub(r"--[^\n]*", "", sql)
    body = code[code.index("(") + 1:code.rindex(")")]
    parts, depth, current, quote = [], 0, "", False
    for ch in body:
        if ch == "'":
            quote = not quote
        if not quote:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                parts.append(current)
                current = ""
                continue
        current += ch
    parts.append(current)
    tail = code[code.rindex(")") + 1:].strip().rstrip(";").strip()
    return [" ".join(p.split()) for p in parts if p.strip()], tail


def short(names, limit=8):
    names = sorted(names)
    if len(names) <= limit:
        return ", ".join(names)
    return ", ".join(names[:limit]) + f", ... (+{len(names) - limit})"


def main():
    root, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="touches-"))

    # The four databases: both schemas, each with and without its triggers.
    files = {}
    for part, label in (("storage", "store"), ("search", "index")):
        full = work / f"{label}.db"
        connection = sqlite3.connect(full)
        for migration in sorted((root / "migrations" / part).glob("*.sql")):
            connection.executescript(migration.read_text())
        connection.close()
        bareless = work / f"{label}_notrig.db"
        shutil.copy(full, bareless)
        drop_triggers(bareless)
        files[label] = {"full": full, "notrig": bareless}

    store_tables, store_triggers = catalog(files["store"]["full"], "store")
    index_tables, index_triggers = catalog(files["index"]["full"], "index")
    triggers = {**store_triggers, **index_triggers}
    tables = {("store", n): t for n, t in store_tables.items()}
    tables.update({("index", n): t for n, t in index_tables.items()})
    views = {n for (_, n), t in tables.items() if t["kind"] == "view"}
    collisions = sorted(set(store_tables) & set(index_tables))
    param = (root / "queries/storage/read/create_param.sql").read_text()

    lookups = {
        "storage": {"param": "temp", **{n: "store" for n in store_tables}},
        "search": {**{n: "store" for n in store_tables}, **{n: "index" for n in index_tables}, "param": "temp"},
    }

    connections = {}
    for part in ("storage", "search"):
        for variant in ("full", "notrig"):
            for fk in (True, False):
                connections[part, variant, fk] = open_as(part, files["store"][variant], files["index"][variant], param, fk)

    # Each trigger's own body: the trigger alone, fired by a synthetic write.
    def synthetic(trigger):
        table = tables[trigger["db"], trigger["table"]]
        if trigger["event"] == "INSERT":
            return f"INSERT INTO {table['name']} DEFAULT VALUES"
        if trigger["event"] == "DELETE":
            return f"DELETE FROM {table['name']}"
        column = trigger["of"][0] if trigger["of"] else next(c["name"] for c in table["columns"] if not c["hidden"])
        return f"UPDATE {table['name']} SET {column} = {column}"

    bodies, fires, body_errors = {}, {}, {}
    for name, trigger in store_triggers.items():
        statement = synthetic(trigger)
        alone = work / f"only_{name}.db"
        shutil.copy(files["store"]["full"], alone)
        drop_triggers(alone, keep=(name,))
        without = work / f"without_{name}.db"
        shutil.copy(files["store"]["full"], without)
        drop_triggers(without, keep=set(store_triggers) - {name})
        seen = {}
        for key, path, fk in (("on", alone, True), ("off", alone, False), ("without", without, True)):
            connection, recorder = open_as("storage", path, None, param, fk)
            seen[key], error = prepare(connection, recorder, statement, lookups["storage"])
            if error:
                body_errors[name] = error
            connection.close()
        connection, recorder = connections["storage", "notrig", True]
        base, _ = prepare(connection, recorder, statement, lookups["storage"])
        connection, recorder = connections["storage", "full", True]
        whole, _ = prepare(connection, recorder, statement, lookups["storage"])
        body = {}
        for row in seen["on"] - base:
            body[row] = row not in seen["off"]
        bodies[name] = body
        fired_with = {r[4] for r in whole if r[4] in triggers}
        fired_without = {r[4] for r in seen["without"] if r[4] in triggers}
        fires[name] = sorted(fired_with - fired_without - {name})
        alone.unlink()
        without.unlink()

    # Every canonical statement.
    statements = []
    touches = []
    failures = []
    odd_sources = set()
    explain_differs = []
    for path in sorted((root / "queries").rglob("*.sql")):
        relative = path.relative_to(root / "queries").with_suffix("")
        part = relative.parts[0]
        profile = relative.parts[1] if part == "storage" else "search"
        name = relative.name
        text = path.read_text()
        sets = {key: set() for key in ("A", "B", "C", "D")}
        pieces = split(text)
        for statement in pieces:
            for key, variant, fk in (("A", "full", True), ("B", "full", False), ("C", "notrig", False), ("D", "notrig", True)):
                connection, recorder = connections[part, variant, fk]
                rows, error = prepare(connection, recorder, statement, lookups[part])
                sets[key] |= rows
                if key == "A":
                    explained = rows
                if error and key == "A":
                    failures.append((f"{profile}/{name}", error))
            # A cross-check that EXPLAIN authorizes what a real prepare does:
            # the statement run for real with NULL parameters, rolled back.
            connection, recorder = connections[part, "full", True]
            connection.execute("BEGIN")
            real, _ = prepare(connection, recorder, statement, lookups[part], explain=False)
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            if real != explained:
                explain_differs.append((f"{profile}/{name}", sorted(real ^ explained, key=str)))
        fired = {r[4] for r in sets["A"] if r[4] in triggers}
        entry = {"name": name, "profile": profile, "part": part, "id": f"{profile}/{name}", "pieces": len(pieces),
                 "fired": sorted(fired), "inserts": insert_targets(text), "rows": set()}
        for row in sets["A"]:
            action, database, table, column, source = row
            via_fk = row not in sets["B"]
            via_view = source if source in views else ""
            if source in triggers:
                via_trigger = source
                if row in sets["D"]:
                    odd_sources.add((entry["id"], source))
            elif row in sets["D"]:
                via_trigger = ""
            else:
                candidates = sorted(t for t in fired if row in bodies.get(t, {}))
                via_trigger = "|".join(candidates) if candidates else "?"
            entry["rows"].add((action, database, table, column, via_trigger, via_view, int(via_fk)))
        statements.append(entry)
        for row in sorted(entry["rows"]):
            touches.append((name, profile) + row)

    with open(out / "touches.tsv", "w") as f:
        f.write("statement\tprofile\taction\ttable\tcolumn\tvia_trigger\tvia_view\tvia_fk\tdb\n")
        for name, profile, action, database, table, column, via_trigger, via_view, via_fk in touches:
            f.write(f"{name}\t{profile}\t{action}\t{table}\t{column}\t{via_trigger}\t{via_view}\t{via_fk}\t{database}\n")

    # Per column and per table: which statements, by which route.
    def route(rows):
        """The strongest route among a statement's rows to one target."""
        if any(not r[4] and not r[6] for r in rows):
            return "direct"
        if any(r[4] for r in rows):
            return "trigger"
        return "fk"

    by_column = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(set)))
    by_table = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(set)))
    for entry in statements:
        groups_c = collections.defaultdict(list)
        groups_t = collections.defaultdict(list)
        for r in entry["rows"]:
            action, database, table, column = r[:4]
            if action in ("READ", "UPDATE") and column:
                groups_c[(database, table, column), action].append(r)
            groups_t[(database, table), action].append(r)
            groups_t[(database, table), "READ" if action == "READ" else "WRITE"].append(r)
        for (target, action), rows in groups_c.items():
            by_column[target][action][route(rows)].add(entry["id"])
        for (target, action), rows in groups_t.items():
            by_table[target][action][route(rows)].add(entry["id"])
        for schema, table, listed in entry["inserts"]:
            database = lookups[entry["part"]].get(table, "?") if schema in (None, "main") else {"store": "store", "temp": "temp"}.get(schema, schema)
            if (database, table) not in tables:
                continue
            for c in tables[database, table]["columns"]:
                if c["hidden"]:
                    continue
                if listed is None or c["name"] in listed:
                    by_column[database, table, c["name"]]["INSERT"]["direct"].add(entry["id"])
    # Columns a trigger body's own INSERT names.
    trigger_inserts = collections.defaultdict(set)
    for name, trigger in triggers.items():
        body_text = trigger["sql"].split("BEGIN", 1)[1] if "BEGIN" in trigger["sql"] else trigger["sql"]
        for schema, table, listed in insert_targets(body_text):
            if (trigger["db"], table) in tables:
                for c in tables[trigger["db"], table]["columns"]:
                    if not c["hidden"] and (listed is None or c["name"] in listed):
                        trigger_inserts[trigger["db"], table, c["name"]].add(name)

    order = sorted(tables, key=lambda k: (0 if k[0] == "store" else 1, k[1]))
    column_rows = []
    with open(out / "columns.tsv", "w") as f:
        f.write("db\ttable\tkind\tcid\tcolumn\ttype\tnotnull\tdefault\tpk\thidden\tindexes\t"
                "n_read_direct\tn_update_direct\tn_read_trigger_only\tn_update_trigger_only\tn_read_fk_only\tn_update_fk_only\tn_insert_named\t"
                "readers_direct\tupdaters_direct\treaders_trigger_only\tupdaters_trigger_only\treaders_fk_only\tupdaters_fk_only\tinserters_named\ttrigger_inserters\n")
        for key in order:
            table = tables[key]
            for c in table["columns"]:
                got = by_column.get((key[0], key[1], c["name"]), {})
                rd, ud = got.get("READ", {}), got.get("UPDATE", {})
                ins = got.get("INSERT", {}).get("direct", set())
                inx = [i["name"] for i in table["indexes"] if c["name"] in i["keys"]]
                row = {
                    "db": key[0], "table": key[1], "kind": table["kind"], "column": c["name"], "type": c["type"], "hidden": c["hidden"],
                    "read_direct": rd.get("direct", set()), "read_trigger": rd.get("trigger", set()), "read_fk": rd.get("fk", set()),
                    "update_direct": ud.get("direct", set()), "update_trigger": ud.get("trigger", set()), "update_fk": ud.get("fk", set()),
                    "insert": ins, "trigger_insert": trigger_inserts.get((key[0], key[1], c["name"]), set()), "indexes": inx,
                }
                column_rows.append(row)
                default = "" if c["default"] is None else c["default"]
                f.write("\t".join(str(x) for x in (
                    key[0], key[1], table["kind"], c["cid"], c["name"], c["type"], c["notnull"], default, c["pk"], c["hidden"], ", ".join(inx),
                    len(row["read_direct"]), len(row["update_direct"]), len(row["read_trigger"]), len(row["update_trigger"]),
                    len(row["read_fk"]), len(row["update_fk"]), len(ins),
                    short(row["read_direct"]), short(row["update_direct"]), short(row["read_trigger"]), short(row["update_trigger"]),
                    short(row["read_fk"]), short(row["update_fk"]), short(ins), short(row["trigger_insert"]),
                )) + "\n")

    table_rows = []
    with open(out / "tables.tsv", "w") as f:
        f.write("db\ttable\tkind\tstrict\twithout_rowid\tn_columns\tn_read_direct\tn_read_trigger_only\tn_read_fk_only\t"
                "n_write_direct\tn_write_trigger_only\tn_write_fk_only\tn_insert_direct\tn_update_direct\tn_delete_direct\t"
                "n_triggers\ttriggers\tn_indexes\tindexes\n")
        for key in order:
            table = tables[key]
            got = by_table.get(key, {})
            n = lambda action, how: len(got.get(action, {}).get(how, set()))
            row = {"db": key[0], "table": key[1], "kind": table["kind"], "columns": len(table["columns"]),
                   "read": n("READ", "direct"), "read_trigger": n("READ", "trigger"), "read_fk": n("READ", "fk"),
                   "write": n("WRITE", "direct"), "write_trigger": n("WRITE", "trigger"), "write_fk": n("WRITE", "fk"),
                   "insert": n("INSERT", "direct"), "update": n("UPDATE", "direct"), "delete": n("DELETE", "direct"),
                   "triggers": table["triggers"], "indexes": [i["name"] for i in table["indexes"]]}
            table_rows.append(row)
            f.write("\t".join(str(x) for x in (
                key[0], key[1], table["kind"], table["strict"], table["wr"], row["columns"], row["read"], row["read_trigger"], row["read_fk"],
                row["write"], row["write_trigger"], row["write_fk"], row["insert"], row["update"], row["delete"],
                len(row["triggers"]), ", ".join(row["triggers"]), len(row["indexes"]), ", ".join(row["indexes"]),
            )) + "\n")

    # The report.
    lines = []
    say = lines.append
    say(f"SQLite {sqlite3.sqlite_version}")
    counts = collections.Counter(e["profile"] for e in statements)
    say(f"statements: {len(statements)} files ({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))}); "
        f"files holding more than one statement: {[(e['id'], e['pieces']) for e in statements if e['pieces'] != 1]}")
    say(f"prepared without error: {len(statements) - len({n for n, _ in failures})}; failed: {len({n for n, _ in failures})}")
    for name, error in failures:
        say(f"  FAILED {name}: {error}")
    say(f"EXPLAIN vs real prepare, statements whose authorizer rows differ: {len(explain_differs)} {explain_differs[:5]}")
    ids = collections.Counter(e["name"] for e in statements)
    say(f"statement basenames shared by two profiles: {sorted(n for n, c in ids.items() if c > 1)}")
    say(f"table names shared by both schemas: {collisions}; CTE/view source equal to a trigger name: {sorted(odd_sources)}")
    say(f"triggers: store {len(store_triggers)}, index {len(index_triggers)}; views: {sorted(views)}; trigger synthetic prepare errors: {body_errors}")
    unresolved = sorted({(t[0], t[1]) for t in touches if t[6] == "?"})
    say(f"rows reached through a trigger the differential could not name: {unresolved}")
    unknown = sorted({(t[3], t[4]) for t in touches if (t[3], t[4]) not in tables and t[3] != "temp"})
    say(f"touched tables outside both schemas and temp: {unknown}")
    say(f"temp tables touched: {sorted({(t[4], t[2]) for t in touches if t[3] == 'temp'})}")
    pseudo = sorted({f"{t[3]}.{t[4]}.{t[5]}" for t in touches if (t[3], t[4]) in tables and t[5] and t[5] not in {c['name'] for c in tables[t[3], t[4]]['columns']}})
    say(f"columns the authorizer named that table_xinfo does not list: {pseudo}")
    say(f"rows: touches.tsv {len(touches)}, columns.tsv {len(column_rows)}, tables.tsv {len(table_rows)}")

    say("\n== TABLES ==")
    say("db.table [kind] cols | readers direct/trigger-only/fk-only | writers direct/trigger-only/fk-only (direct I/U/D) | triggers | indexes")
    for r in table_rows:
        say(f"{r['db']}.{r['table']} [{r['kind']}] {r['columns']} | R {r['read']}/{r['read_trigger']}/{r['read_fk']} | "
            f"W {r['write']}/{r['write_trigger']}/{r['write_fk']} (I{r['insert']} U{r['update']} D{r['delete']}) | "
            f"triggers {len(r['triggers'])}: {', '.join(r['triggers']) or '-'} | indexes {len(r['indexes'])}: {', '.join(r['indexes']) or '-'}")

    real = [r for r in column_rows if r["kind"] != "shadow"]
    say("\n== COLUMNS NO STATEMENT READS DIRECTLY ==")
    say("(table.column: trigger-only readers / fk-only readers / direct updaters / trigger-only updaters / statements naming it in an INSERT / indexes keyed on it)")
    for r in real:
        if not r["read_direct"]:
            say(f"{r['db']}.{r['table']}.{r['column']}{' [hidden]' if r['hidden'] else ''}: trig {len(r['read_trigger'])} / fk {len(r['read_fk'])} / "
                f"upd {len(r['update_direct'])} / trig-upd {len(r['update_trigger'])} / ins {len(r['insert'])} / idx {', '.join(r['indexes']) or '-'}")
    say("\n== COLUMNS READ DIRECTLY BY 1 OR 2 STATEMENTS ==")
    for r in real:
        if 1 <= len(r["read_direct"]) <= 2:
            say(f"{r['db']}.{r['table']}.{r['column']}: {', '.join(sorted(r['read_direct']))}")
    say("\n== COLUMNS WRITTEN (UPDATE by any route, or named by an INSERT) BUT NEVER READ BY ANY ROUTE ==")
    for r in real:
        reads = r["read_direct"] | r["read_trigger"] | r["read_fk"]
        writes = r["update_direct"] | r["update_trigger"] | r["update_fk"]
        if not reads and (writes or r["insert"] or r["trigger_insert"]):
            say(f"{r['db']}.{r['table']}.{r['column']}: updaters {len(writes)} ({short(writes, 4)}), inserters {len(r['insert'])} ({short(r['insert'], 4)}), trigger inserters {short(r['trigger_insert'], 4) or '-'}")
    say("\n== COLUMNS WRITTEN BUT READ ONLY THROUGH TRIGGERS OR FOREIGN KEYS (no direct read) ==")
    for r in real:
        reads = r["read_trigger"] | r["read_fk"]
        writes = r["update_direct"] | r["update_trigger"] | r["update_fk"]
        if not r["read_direct"] and reads and (writes or r["insert"] or r["trigger_insert"]):
            say(f"{r['db']}.{r['table']}.{r['column']}: trigger-only readers {len(r['read_trigger'])}, fk-only readers {len(r['read_fk'])}, updaters {len(writes)}, inserters {len(r['insert'])}")
    say("\n== COLUMNS READ (any route) BUT NEVER UPDATED (any route); inserts aside ==")
    say("(table.column: direct readers / trigger-only readers / fk-only readers / statements naming it in an INSERT / trigger bodies inserting it)")
    for r in real:
        reads = r["read_direct"] | r["read_trigger"] | r["read_fk"]
        writes = r["update_direct"] | r["update_trigger"] | r["update_fk"]
        if reads and not writes:
            say(f"{r['db']}.{r['table']}.{r['column']}{' [hidden]' if r['hidden'] else ''}: {len(r['read_direct'])} / {len(r['read_trigger'])} / {len(r['read_fk'])} / ins {len(r['insert'])} / trig-ins {len(r['trigger_insert'])}")
    say("\n== COLUMNS NEITHER READ NOR UPDATED NOR NAMED BY AN INSERT ==")
    for r in real:
        if not (r["read_direct"] | r["read_trigger"] | r["read_fk"] | r["update_direct"] | r["update_trigger"] | r["update_fk"] | r["insert"] | r["trigger_insert"]):
            say(f"{r['db']}.{r['table']}.{r['column']}{' [hidden]' if r['hidden'] else ''}")

    say("\n== TRIGGERS (store schema) ==")
    with open(out / "triggers.tsv", "w") as f:
        f.write("trigger\ttable\ttiming\tevent\tof\twhen\taction\ttarget_table\tcolumn\tsource\tvia_fk\n")
        firing = collections.defaultdict(set)
        for entry in statements:
            for t in entry["fired"]:
                firing[t].add(entry["id"])
        for name, trigger in store_triggers.items():
            body = bodies[name]
            reads = collections.defaultdict(set)
            fk_reads = collections.defaultdict(set)
            writes, fk_writes = [], []
            updates = collections.defaultdict(set)
            fk_updates = collections.defaultdict(set)
            through = set()
            for (action, database, table, column, source), fk in sorted(body.items(), key=str):
                f.write(f"{name}\t{trigger['table']}\t{trigger['timing']}\t{trigger['event']}\t{','.join(trigger['of'])}\t{int(trigger['when'])}\t{action}\t{table}\t{column}\t{source or ''}\t{int(fk)}\n")
                if source and source != name:
                    through.add(source)
                if action == "READ":
                    (fk_reads if fk else reads)[table].add(column or "(row)")
                elif action == "UPDATE":
                    (fk_updates if fk else updates)[table].add(column)
                else:
                    (fk_writes if fk else writes).append(f"{action} {table}")
            fmt = lambda d: "; ".join(f"{t}({', '.join(sorted(cs))})" for t, cs in sorted(d.items())) or "-"
            event = trigger["event"] + (f" OF {', '.join(trigger['of'])}" if trigger["of"] else "")
            say(f"{name}: {trigger['timing']} {event} ON {trigger['table']}{' WHEN' if trigger['when'] else ''}")
            say(f"    reads: {fmt(reads)}")
            w = sorted(set(writes)) + [f"UPDATE {t}({', '.join(sorted(cs))})" for t, cs in sorted(updates.items())]
            say(f"    writes: {'; '.join(w) or '- (none: a guard)'}")
            if fk_reads or fk_updates or fk_writes:
                w = sorted(set(fk_writes)) + [f"UPDATE {t}({', '.join(sorted(cs))})" for t, cs in sorted(fk_updates.items())]
                say(f"    only with foreign keys on (key checks and ON DELETE/UPDATE actions SQLite adds once the trigger is there): reads {fmt(fk_reads)}; writes {'; '.join(w) or '-'}")
            if through:
                say(f"    through view/CTE: {', '.join(sorted(through))}")
            if fires[name]:
                say(f"    its writes fire: {', '.join(fires[name])}")
            say(f"    fired by {len(firing[name])} statements: {short(firing[name], 6) or '-'}")

    say("\n== 20 STATEMENTS TOUCHING THE MOST TABLES ==")
    say("(base and virtual tables of both schemas, any action, any route; temp.param, views and sqlite_master left out; then the count by direct access alone, then triggers fired)")
    ranking = []
    for entry in statements:
        every = {(r[1], r[2]) for r in entry["rows"] if (r[1], r[2]) in tables and tables[r[1], r[2]]["kind"] != "view"}
        direct = {(r[1], r[2]) for r in entry["rows"] if (r[1], r[2]) in tables and tables[r[1], r[2]]["kind"] != "view" and not r[4] and not r[6]}
        ranking.append((len(every), len(direct), entry["id"], len(entry["fired"])))
    for every, direct, name, fired in sorted(ranking, key=lambda x: (-x[0], -x[1], x[2]))[:20]:
        say(f"{name}: {every} tables ({direct} direct, {fired} triggers)")
    say("by direct access alone:")
    for every, direct, name, fired in sorted(ranking, key=lambda x: (-x[1], -x[0], x[2]))[:20]:
        say(f"{name}: {direct} direct ({every} any route)")

    say("\n== SUMMARY TABLES: columns (name type) ==")
    for name in SUMMARIES:
        table = tables["store", name]
        say(f"{name} ({len(table['columns'])}): " + ", ".join(f"{c['name']} {c['type']}" for c in table["columns"]))
    common = set.intersection(*[{(c["name"], c["type"]) for c in tables["store", n]["columns"]} for n in SUMMARIES])
    say(f"in all six: {sorted(common)}")
    spread = collections.defaultdict(list)
    for name in SUMMARIES:
        for c in tables["store", name]["columns"]:
            spread[c["name"]].append(f"{name.replace('_summary', '')}:{c['type']}")
    for column, where in sorted(spread.items(), key=lambda x: (-len(x[1]), x[0])):
        say(f"  {column}: {len(where)} of 6 ({', '.join(where)})")
    say("\n== SUMMARY TABLES: as declared ==")
    for name in SUMMARIES:
        parts, tail = declared(tables["store", name]["sql"])
        say(f"{name} [{tail}]")
        for p in parts:
            say(f"    {p}")
    say("\n== CORE TABLES: as declared ==")
    for name in DECLARED:
        parts, tail = declared(tables["store", name]["sql"])
        say(f"{name} [{tail}]")
        for p in parts:
            say(f"    {p}")

    (out / "report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    for connection, _ in connections.values():
        connection.close()
    shutil.rmtree(work)


main()
