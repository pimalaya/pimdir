"""Query-path bench: io-pimdir's compiled `is:unread` against the store's
keyset page, over a canonical store of N mail placements.

Usage: python3 -I query_bench.py SCHEMA_SQL SEARCH_SCHEMA_SQL DATA_DIR N COLLECTIONS
"""

import importlib.util
import os
import sqlite3
import statistics
import sys
import time

spec = importlib.util.spec_from_file_location(
    "write_bench", os.path.join(os.path.dirname(os.path.abspath(__file__)), "write_bench.py"))
sys.argv, argv = sys.argv[:3], sys.argv
wb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wb)
sys.argv = argv

SEARCH_SCHEMA = open(sys.argv[2]).read()
DATA = sys.argv[3]
N = int(sys.argv[4])
COLLECTIONS = int(sys.argv[5])

store = os.path.join(DATA, f"store-{N}-{COLLECTIONS}.db")
index = os.path.join(DATA, f"index-{N}-{COLLECTIONS}.db")

if not os.path.exists(store):
    began = time.perf_counter()
    wb.build("canonical", store, N)
    # Spread the mail over COLLECTIONS mailboxes of one account.
    conn = sqlite3.connect(store, isolation_level=None)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("BEGIN")
    for c in range(1, COLLECTIONS):
        conn.execute("INSERT INTO collections(id, account, kind, name) VALUES(?, 'acct',"
                     " 'message/rfc822', ?)", (f"acct/box{c}", f"box{c}"))
    if COLLECTIONS > 1:
        rows = conn.execute("SELECT link_id, seq FROM items").fetchall()
        for link_id, seq in rows:
            c = seq % COLLECTIONS
            if c:
                # Move the placement: its children follow by ON UPDATE CASCADE.
                conn.execute("UPDATE items SET collection = ? WHERE collection = 'acct/INBOX'"
                             " AND link_id = ?", (f"acct/box{c}", link_id))
    conn.execute("COMMIT")
    conn.execute("ANALYZE")
    conn.close()
    print(f"built store in {time.perf_counter() - began:.1f}s")

if os.path.exists(index):
    os.remove(index)
conn = sqlite3.connect(index, isolation_level=None)
conn.executescript(SEARCH_SCHEMA)
conn.execute("ATTACH ? AS store", (store,))
conn.execute("BEGIN")
conn.execute("""INSERT INTO placement(collection, seq, link_id, hash)
    SELECT collection, seq, link_id, object_hash FROM store.items WHERE deleted = 0""")
conn.execute("""INSERT INTO flag(flag, collection, seq)
    SELECT f.flag, f.collection, i.seq FROM store.placement_flag f
    JOIN store.items i ON i.collection = f.collection AND i.link_id = f.link_id""")
conn.execute("COMMIT")
conn.execute("""CREATE TEMP TABLE term_match(term INTEGER, collection TEXT, akey TEXT,
    seq INTEGER, src TEXT, rank REAL)""")
conn.execute("CREATE TEMP TABLE param(slot TEXT NOT NULL, position INTEGER NOT NULL,"
             " value ANY, PRIMARY KEY (slot, position)) STRICT")
for at, (cid,) in enumerate(conn.execute("SELECT id FROM store.collections").fetchall()):
    conn.execute("INSERT INTO temp.param VALUES('collections', ?, ?)", (at, cid))

LIVE = """WITH live(akey, account, seq) AS (SELECT DISTINCT ifnull(c.account, ''), c.account, i.seq
 FROM store.items i JOIN store.collections c ON c.id = i.collection
 WHERE i.deleted = 0 AND i.retained_at IS NULL),
hits(akey, account, seq) AS (SELECT akey, account, seq FROM live WHERE (NOT (CASE WHEN (akey, seq) IN
 (SELECT ifnull(c.account, ''), x.seq FROM (SELECT collection, seq FROM flag WHERE flag = '\\Seen') x
  JOIN store.collections c ON c.id = x.collection) THEN 1 ELSE 0 END))),
matched(akey, seq, src, rank) AS (SELECT akey, seq, src, rank FROM temp.term_match WHERE term IN ())
"""
PLACEMENTS = """FROM store.items i JOIN store.collections c ON c.id = i.collection
 WHERE i.seq = h.seq AND ifnull(c.account, '') = h.akey AND i.deleted = 0 AND i.retained_at IS NULL"""
COMPILED_PAGE = LIVE + f"""SELECT h.account, h.seq, NULL AS rank,
 (SELECT max(i.sort_key) {PLACEMENTS}) AS sort_key,
 (SELECT max(c.kind IN ('text/vcard', 'application/octet-stream')) {PLACEMENTS}) AS undated,
 '' AS title
FROM hits h ORDER BY undated ASC, CASE WHEN undated = 0 THEN sort_key END DESC,
 CASE WHEN undated = 1 THEN sort_key END ASC, h.seq ASC, h.akey ASC LIMIT 51 OFFSET :offset"""
COMPILED_COUNT = LIVE + "SELECT count(*) FROM hits"

QUERIES = os.path.join(os.path.dirname(sys.argv[1]), "..", "..", "queries", "storage", "read")


def canonical(name):
    text = open(os.path.join(QUERIES, f"{name}.sql")).read()
    text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("--"))
    return text.replace("FROM placement_flag", "FROM store.placement_flag") \
        .replace("FROM items", "FROM store.items").replace("JOIN items", "JOIN store.items") \
        .replace("JOIN mail_summary", "JOIN store.mail_summary") \
        .replace("FROM mail_summary", "FROM store.mail_summary")


PAGE = canonical("list_mail_page_filtered")
COUNT = canonical("count_mail")
UNREAD = canonical("count_unread")


def timed(sql, params, runs=5):
    samples, rows = [], None
    for _ in range(runs):
        began = time.perf_counter()
        rows = conn.execute(sql, params).fetchall()
        samples.append(time.perf_counter() - began)
    return statistics.median(samples) * 1000, rows


page_params = {"since": None, "after_key": None, "after_seq": None, "after_collection": None,
               "seen": 0, "attachment": None, "limit": 50}
cases = [
    ("compiled is:unread, page 1", COMPILED_PAGE, {"offset": 0}),
    ("compiled is:unread, page at offset 5000", COMPILED_PAGE, {"offset": 5000}),
    ("compiled is:unread, count", COMPILED_COUNT, {}),
    ("store list_mail_page_filtered seen=0, page 1", PAGE, page_params),
    ("store count_mail seen=0", COUNT, {"seen": 0, "attachment": None, "since": None}),
    ("store count_unread", UNREAD, {"attachment": None, "since": None}),
]
print(f"N={N} collections={COLLECTIONS}")
for name, sql, params in cases:
    ms, rows = timed(sql, params)
    print(f"  {name:48s} {ms:9.2f} ms  ({len(rows)} rows, first {rows[0] if rows else None})")

# The deep page of the store's own keyset walk: the cursor of row 5000.
cursor = conn.execute(PAGE, {**page_params, "limit": 5001}).fetchall()[-1]
deep = {**page_params, "after_key": cursor[5], "after_seq": cursor[1], "after_collection": cursor[0]}
ms, rows = timed(PAGE, deep)
print(f"  {'store list_mail_page_filtered seen=0, after 5000':48s} {ms:9.2f} ms  ({len(rows)} rows)")
