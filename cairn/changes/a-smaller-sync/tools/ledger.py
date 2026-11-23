#!/usr/bin/env python3
"""The ledger of a-smaller-sync (design.md 5.3), standard library only.

  ledger.py split BASE.md > rules.tsv
  ledger.py check BASE.md NEW.md rules.tsv [--budget]

Units. A heading, a table row, a list item (with its continuation lines) is
one unit; a paragraph is split into sentences, a bold lead-in ending in a
full stop being a sentence of its own. Backticked spans, "e.g.", "i.e.",
"etc.", decimals and section numbers never split. Key words are read outside
backticks and double quotes, in capitals only.

Targets. A kept, merged or tabled row names new_section, new_anchor,
new_sentence and new_incipit:

- prose: new_anchor is a bold lead-in of NEW.md (the block running from it
  to the next lead-in, heading or table), or empty for the whole section;
  the target is the unit of that scope containing new_incipit, new_sentence
  (its 1-based index in the scope, the section heading not counted) only
  telling apart several units containing it;
- table (state tabled, or new_sentence "row/col"): new_anchor is a text of
  the paragraph right before the table, or its first header cell; the row
  is the one whose first cell contains new_incipit; col, a 1-based index or
  a header cell, names the cell the key word is read from (the whole row
  holding the identifiers and numbers).

A row whose new_section is not its old_section names a stub: the old_id of
another row whose target, in the old section, holds "§<new_section>", or
"new:<text>", a unit of the old section containing <text> and that
reference.

Rows whose old_id starts with "n" are new-only: a unit of NEW.md no base
sentence maps to (a pointer, a table caption, a heading), class pointer,
heading, note, reason or example, state new-only. Every other unit of NEW.md
but headings, table headers and notes MUST be a target, key word or not:
an unmarked statement binds as MUST.
"""

import re
import sys

COLUMNS = [
    "old_id", "old_section", "incipit", "class", "keyword", "family",
    "state", "new_section", "new_anchor", "new_sentence", "new_incipit",
    "stub", "nuance", "review",
]
CLASSES = {"rule", "definition", "pointer", "reason", "example", "note",
           "heading"}
KEYWORDS = {"MUST", "MUST NOT", "SHOULD", "SHOULD NOT", "MAY", "binds",
            "none"}
STATES = {"kept", "merged", "tabled", "cut-informative"}
CUTTABLE = {"reason", "example", "note"}
NEW_ONLY_CLASSES = {"pointer", "heading", "note", "reason", "example"}

BUDGET = {0: 250, 1: 160, 2: 780, 3: 570, 4: 2480, 5: 3750, 6: 1500,
          7: 1250, 8: 700, 9: 950, 10: 550, 11: 900, 12: 160}

KW_RE = re.compile(
    r"\b(MUST NOT|MUST|SHALL NOT|SHALL|REQUIRED|SHOULD NOT|SHOULD|"
    r"NOT RECOMMENDED|RECOMMENDED|MAY|OPTIONAL)\b")
KW_NORM = {"MUST NOT": "MUST NOT", "MUST": "MUST", "SHALL NOT": "MUST NOT",
           "SHALL": "MUST", "REQUIRED": "MUST", "SHOULD NOT": "SHOULD NOT",
           "SHOULD": "SHOULD", "NOT RECOMMENDED": "SHOULD NOT",
           "RECOMMENDED": "SHOULD", "MAY": "MAY", "OPTIONAL": "MAY"}
KW_RANK = ["MUST NOT", "MUST", "SHOULD NOT", "SHOULD", "MAY"]
LEVEL = {"MUST NOT": 3, "MUST": 3, "binds": 3, "SHOULD NOT": 2, "SHOULD": 2,
         "MAY": 1, "none": 0}

ABBREVIATIONS = ["e.g.", "i.e.", "etc.", "cf.", "vs.", "approx.", "resp."]
SPLIT_RE = re.compile(r"[.?!](?:\*\*|\*|\)|\"|')*(?=\s+[A-Z`*§\[(\"0-9])")
LEADIN_RE = re.compile(r"^(?:\*Note:\*\s+)?\*\*(.+?)\*\*")


class Unit:
    """One sentence, heading, list item or table row."""

    def __init__(self, kind, section, line, n, text, note=False,
                 leadin=None, first=True, indent=0):
        self.kind = kind          # heading, theader, trow, item, sentence
        self.section = section
        self.line = line
        self.n = n
        self.text = text
        self.note = note
        self.leadin = leadin      # bold lead-in opening this unit
        self.first = first        # first unit of its paragraph or item
        self.indent = indent

    @property
    def oid(self):
        return "o%02d-L%d-s%d" % (self.section, self.line, self.n)


def mask(text):
    """Text of the same length where nothing splits or counts: backticked
    spans, abbreviations."""
    out = re.sub(r"`[^`]*`", lambda m: "`" + "x" * (len(m.group()) - 2) + "`",
                 text)
    for abbr in ABBREVIATIONS:
        out = out.replace(abbr, abbr.replace(".", "x"))
    return out


def sentences(text):
    masked = mask(text)
    cuts = [0]
    for m in SPLIT_RE.finditer(masked):
        cuts.append(m.end())
    cuts.append(len(text))
    out = []
    for a, b in zip(cuts, cuts[1:]):
        s = text[a:b].strip()
        if s:
            out.append(s)
    return out


def parse(text):
    """Every unit of a document, in order."""
    lines = text.split("\n")
    units = []
    section = 0
    fence = False
    i = 0
    while i < len(lines):
        line = lines[i]
        lineno = i + 1
        stripped = line.strip()
        if stripped.startswith("```"):
            fence = not fence
            i += 1
            continue
        if fence or not stripped:
            i += 1
            continue
        m = re.match(r"^(#+)\s+(.*)$", line)
        if m:
            title = m.group(2).strip()
            if len(m.group(1)) == 2:
                sm = re.match(r"^(\d+)\.\s", title)
                if sm:
                    section = int(sm.group(1))
            units.append(Unit("heading", section, lineno, 1, title))
            i += 1
            continue
        if stripped.startswith("|"):
            if re.match(r"^\|[\s:|-]+\|?$", stripped):
                i += 1
                continue
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            kind = ("theader" if re.match(r"^\|[\s:|-]+\|?$", nxt)
                    else "trow")
            units.append(Unit(kind, section, lineno, 1, stripped))
            i += 1
            continue
        im = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", line)
        if im and not stripped.startswith("*Note:*"):
            body = im.group(3)
            j = i + 1
            while (j < len(lines) and lines[j].strip()
                   and lines[j].startswith(" ")
                   and not re.match(r"^\s*([-*+]|\d+\.)\s", lines[j])):
                body += " " + lines[j].strip()
                j += 1
            lm = LEADIN_RE.match(body)
            units.append(Unit("item", section, lineno, 1, body.strip(),
                              leadin=lm.group(1) if lm else None,
                              indent=len(im.group(1))))
            i = j
            continue
        body = stripped
        j = i + 1
        while (j < len(lines) and lines[j].strip()
               and not lines[j].lstrip().startswith(("#", "|", "```"))
               and not re.match(r"^\s*([-*+]|\d+\.)\s", lines[j])):
            body += " " + lines[j].strip()
            j += 1
        note = body.startswith("*Note:*")
        lm = LEADIN_RE.match(body)
        for n, s in enumerate(sentences(body), 1):
            units.append(Unit("sentence", section, lineno, n, s, note=note,
                              leadin=lm.group(1) if (lm and n == 1) else None,
                              first=(n == 1)))
        i = j
    return units


def keywords(text):
    """The key words of a text, outside backticks and double quotes."""
    clean = re.sub(r"`[^`]*`", " ", text)
    clean = re.sub(r"\"[^\"]*\"", " ", clean)
    return [KW_NORM[k] for k in KW_RE.findall(clean)]


def strongest(text):
    found = set(keywords(text))
    for k in KW_RANK:
        if k in found:
            return k
    return None


def words(text):
    return len(text.split())


def norm(text):
    return " ".join(text.replace("**", "").split())


def incipit(text):
    return " ".join(text.split()[:8])


def is_contents(unit):
    return unit.kind == "item" and re.match(r"^\[[^\]]+\]\(#", unit.text)


def prefill(unit):
    """class and keyword split pre-fills."""
    if unit.kind in ("heading", "theader") or is_contents(unit):
        return "heading", "none"
    if unit.note:
        return "note", "none"
    bare = unit.text.strip()
    if re.fullmatch(r"\*\*[^*]+\*\*:?", bare):
        return "heading", "none"
    k = strongest(unit.text)
    if unit.kind == "item" and unit.section == 2 and unit.leadin:
        return "definition", k or "binds"
    return "rule", k or "binds"


def split(base_path):
    units = parse(open(base_path, encoding="utf-8").read())
    out = sys.stdout
    out.write("\t".join(COLUMNS) + "\n")
    for u in units:
        cls, kw = prefill(u)
        row = {c: "" for c in COLUMNS}
        row.update(old_id=u.oid, old_section=str(u.section),
                   incipit=incipit(u.text).replace("\t", " "),
                   **{"class": cls}, keyword=kw)
        out.write("\t".join(row[c] for c in COLUMNS) + "\n")


def read_ledger(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        if header != COLUMNS:
            raise SystemExit("ledger header is not the design's columns: %r"
                             % header)
        for n, line in enumerate(f, 2):
            line = line.rstrip("\n")
            if not line:
                continue
            cells = line.split("\t")
            cells += [""] * (len(COLUMNS) - len(cells))
            row = dict(zip(COLUMNS, cells))
            row["_line"] = n
            rows.append(row)
    return rows


class Doc:
    """A parsed NEW.md, indexed for target resolution."""

    def __init__(self, text):
        self.text = text
        self.units = parse(text)
        self.sections = {}
        for idx, u in enumerate(self.units):
            u.idx = idx
            self.sections.setdefault(u.section, []).append(u)
        self.tables = {}
        cur = None
        last = None
        for u in self.units:
            if u.kind == "theader":
                caption = ""
                if last is not None and last.kind == "sentence":
                    caption = " ".join(
                        p.text for p in self.units
                        if p.kind == "sentence" and p.line == last.line)
                cur = {"header": cells(u.text), "rows": [],
                       "caption": caption}
                self.tables.setdefault(u.section, []).append(cur)
            elif u.kind == "trow" and cur is not None:
                cur["rows"].append(u)
            else:
                cur = None
            last = u

    def scope(self, section, anchor):
        units = [u for u in self.sections.get(section, [])
                 if not (u.kind == "heading" and u is
                         self.sections[section][0] and section > 0)]
        if not anchor:
            return units, None
        a = norm(anchor).rstrip(".:")
        start = None
        for k, u in enumerate(units):
            if u.leadin and norm(u.leadin).rstrip(".:") == a:
                start = k
                break
        if start is None:
            return None, "anchor %r not found in §%d" % (anchor, section)
        block = [units[start]]
        for u in units[start + 1:]:
            if u.kind in ("heading", "theader", "trow"):
                break
            if u.leadin and u.first and u.indent <= units[start].indent:
                break
            block.append(u)
        return block, None


def cells(row):
    parts = row.strip().strip("|").split("|")
    return [p.strip() for p in parts]


def resolve(doc, row):
    """(unit, keyword text, check text) or an error string."""
    try:
        section = int(row["new_section"])
    except ValueError:
        return "new_section %r is no section" % row["new_section"]
    if section not in doc.sections:
        return "new_section §%d does not exist" % section
    inc = norm(row["new_incipit"])
    if not inc:
        return "new_incipit empty"
    sent = row["new_sentence"].strip()
    if row["state"] == "tabled" or "/" in sent:
        anchor = norm(row["new_anchor"])
        tables = [t for t in doc.tables.get(section, [])
                  if anchor and (anchor in norm(t["caption"]) or
                                 anchor == norm(t["header"][0]))]
        if not tables:
            return "no table %r in §%d" % (row["new_anchor"], section)
        rr, _, cc = sent.partition("/")
        for t in tables:
            hits = [u for u in t["rows"] if inc in norm(cells(u.text)[0])]
            if rr.strip().isdigit():
                k = int(rr) - 1
                hits = [u for u in hits if 0 <= k < len(t["rows"])
                        and t["rows"][k] is u] or hits
            if not hits:
                continue
            u = hits[0]
            cs = cells(u.text)
            cell = u.text
            cc = cc.strip()
            if cc:
                if cc.isdigit():
                    ci = int(cc) - 1
                else:
                    hdr = [norm(h) for h in t["header"]]
                    ci = hdr.index(norm(cc)) if norm(cc) in hdr else -1
                if not 0 <= ci < len(cs):
                    return "no column %r in table %r" % (cc,
                                                         row["new_anchor"])
                cell = cs[ci]
            return u, cell, u.text
        return "no row of table %r in §%d starts %r" % (
            row["new_anchor"], section, row["new_incipit"])
    units, err = doc.scope(section, row["new_anchor"])
    if err:
        return err
    hits = [(k, u) for k, u in enumerate(units, 1) if inc in norm(u.text)]
    if not hits and not row["new_anchor"]:
        head = doc.sections[section][0]
        if head.kind == "heading" and inc in norm(head.text):
            hits = [(0, head)]
    if not hits:
        return "no unit of §%d%s contains %r" % (
            section, (" at %r" % row["new_anchor"]) if row["new_anchor"]
            else "", row["new_incipit"])
    if len(hits) > 1 and sent.isdigit():
        chosen = [h for h in hits if h[0] == int(sent)]
        if not chosen:
            return "new_sentence %s does not hold %r (found at %s)" % (
                sent, row["new_incipit"], ",".join(str(h[0]) for h in hits))
        hits = chosen
    u = hits[0][1]
    return u, u.text, u.text


STRIP_REFS = re.compile(
    r"(?:STORAGE(?:\.md)?\s+)?§\d+(?:\.\d+)*|Annex\s+[A-Z](?:\.\d+)*|"
    r"\bU\+[0-9A-F]+\b")


def identifiers(text):
    return set(re.findall(r"`[^`]+`", text))


def numbers(text):
    clean = re.sub(r"`[^`]*`", " ", text)
    clean = STRIP_REFS.sub(" ", clean)
    clean = re.sub(r"\]\([^)]*\)", "]", clean)
    return set(re.findall(r"\b\d+(?:[.,]\d+)*\b", clean))


def has_ref(text, section):
    clean = re.sub(r"STORAGE(?:\.md)?\s+§\d+", " ", text)
    return re.search(r"§%d(?![\d])" % section, clean) is not None


def keyword_totals(units):
    tot = {k: 0 for k in KW_RANK}
    for u in units:
        for k in keywords(u.text):
            tot[k] += 1
    return tot


def section_words(text):
    """Words per section, as wc -w counts them; the preamble leaves out the
    Contents list, which a rewrite does not choose (design.md 1.3 counts
    296 so)."""
    counts = {}
    section = 0
    skip = False
    for line in text.split("\n"):
        m = re.match(r"^##\s+(\d+)\.\s", line)
        if m:
            section = int(m.group(1))
            skip = False
        elif re.match(r"^##\s+Contents\s*$", line):
            skip = True
            continue
        if skip:
            continue
        counts[section] = counts.get(section, 0) + words(line)
    return counts


def check(base_path, new_path, ledger_path, budget):
    fails = []

    def fail(msg):
        fails.append(msg)

    base_units = parse(open(base_path, encoding="utf-8").read())
    base = {u.oid: u for u in base_units}
    new_text = open(new_path, encoding="utf-8").read()
    doc = Doc(new_text)
    rows = read_ledger(ledger_path)
    by_id = {}
    for r in rows:
        if r["old_id"] in by_id:
            fail("%s: two rows" % r["old_id"])
        by_id[r["old_id"]] = r

    for oid in base:
        if oid not in by_id:
            fail("%s: base sentence has no row (%s)" %
                 (oid, incipit(base[oid].text)))
    targets = {}
    resolved = {}
    for r in rows:
        oid = r["old_id"]
        new_only = oid.startswith("n")
        if not new_only and oid not in base:
            fail("%s: no such base sentence" % oid)
            continue
        if not new_only and norm(r["incipit"]) != norm(
                incipit(base[oid].text)):
            fail("%s: incipit is not the base's (%r)" %
                 (oid, incipit(base[oid].text)))
        cls, kw, st = r["class"], r["keyword"], r["state"]
        if cls not in CLASSES:
            fail("%s: class %r" % (oid, cls))
        if kw not in KEYWORDS:
            fail("%s: keyword %r" % (oid, kw))
        if new_only:
            if st != "new-only":
                fail("%s: a new-only row has state %r" % (oid, st))
            # A unit continuing one base sentence split over several units
            # (a list made of one sentence) names it: "split:<old_id>".
            parent = r.get("review", "").partition("split:")[2].strip()
            split = bool(parent) and parent in base and any(
                p["old_id"] == parent and p["state"] in ("kept", "merged")
                for p in rows)
            if parent and not split:
                fail("%s: splits %r, no kept or merged base sentence"
                     % (oid, parent))
            if cls not in NEW_ONLY_CLASSES and not split:
                fail("%s: new-only row of class %s adds text that binds"
                     % (oid, cls))
        elif st not in STATES:
            fail("%s: state %r" % (oid, st or "(empty)"))
            continue
        if st == "cut-informative":
            if cls not in CUTTABLE:
                fail("%s: a %s is cut" % (oid, cls))
            continue
        res = resolve(doc, r)
        if isinstance(res, str):
            fail("%s: %s" % (oid, res))
            continue
        unit, kwtext, wholetext = res
        resolved[oid] = res
        targets.setdefault(unit.idx, []).append(r)
        if new_only:
            continue
        old = base[oid]
        try:
            moved = int(r["new_section"]) != old.section
        except ValueError:
            moved = False
        if moved and cls != "heading":
            r["_moved"] = True
        if r["nuance"].strip() == "" and cls != "heading":
            for ident in sorted(identifiers(old.text) -
                                identifiers(wholetext)):
                fail("%s: %s missing from its target, no nuance" %
                     (oid, ident))
            for num in sorted(numbers(old.text) - numbers(wholetext)):
                fail("%s: number %s missing from its target, no nuance" %
                     (oid, num))
        r["_kwtext"] = kwtext

    # stubs, once every target is resolved
    for r in rows:
        if not r.get("_moved"):
            continue
        oid = r["old_id"]
        old_sec = base[oid].section
        new_sec = int(r["new_section"])
        stub = r["stub"].strip()
        if not stub:
            fail("%s: moved from §%d to §%d with no stub" %
                 (oid, old_sec, new_sec))
            continue
        if stub.startswith("new:"):
            want = norm(stub[4:])
            ok = [u for u in doc.sections.get(old_sec, [])
                  if want in norm(u.text)]
            text = ok[0].text if ok else None
        else:
            res = resolved.get(stub)
            text = None
            if res is not None and res[0].section == old_sec:
                text = res[2]
        if text is None:
            fail("%s: stub %s names no unit of §%d" % (oid, stub, old_sec))
        elif not has_ref(text, new_sec):
            fail("%s: stub %s in §%d does not cite §%d" %
                 (oid, stub, old_sec, new_sec))

    # key word levels: the keyword column agrees with its sentence; every
    # level a sentence holds is held by its target (binds by MUST or by no
    # key word at all); a target holds no level its sentences lacked
    names = {3: "MUST", 2: "SHOULD", 1: "MAY"}
    for r in rows:
        oid = r["old_id"]
        if oid.startswith("n") or oid not in base or r["keyword"] == "none":
            continue
        s = strongest(base[oid].text)
        if s and LEVEL[s] != LEVEL.get(r["keyword"], -1):
            fail("%s: keyword column %s, the sentence holds %s" %
                 (oid, r["keyword"], s))
        if not s and r["keyword"] != "binds":
            fail("%s: keyword column %s, the sentence holds none" %
                 (oid, r["keyword"]))
    for idx, rs in targets.items():
        unit = doc.units[idx]
        kwtext = None
        lr = set()
        for r in rs:
            if r["old_id"].startswith("n") or r["keyword"] == "none":
                continue
            kwtext = r.get("_kwtext", unit.text)
            lr |= {LEVEL[k] for k in keywords(base[r["old_id"]].text)}
            lr.add(LEVEL.get(r["keyword"], 0))
        if kwtext is None:
            continue
        lt = {LEVEL[k] for k in keywords(kwtext)}
        where = "§%d L%d" % (unit.section, unit.line)
        for r in rs:
            if r["old_id"].startswith("n") or r["keyword"] == "none":
                continue
            ol = {LEVEL[k] for k in keywords(base[r["old_id"]].text)}
            for lv in sorted(ol - lt, reverse=True):
                fail("%s: its %s is not in its target %s (%s)" % (
                    r["old_id"], names[lv], where,
                    strongest(kwtext) or "no key word"))
            if not ol and lt and 3 not in lt:
                fail("%s: binds, its target %s holds only %s" % (
                    r["old_id"], where, strongest(kwtext)))
        for lv in sorted(lt - lr, reverse=True):
            fail("%s %r: holds a %s no row targeting it carries" % (
                where, incipit(unit.text), names[lv]))

    # nothing added
    for u in doc.units:
        if u.idx in targets or u.kind in ("heading", "theader") or u.note:
            continue
        if is_contents(u):
            continue
        what = strongest(u.text) or "binds"
        fail("§%d L%d %r: no row targets it, nothing may be added (%s)" %
             (u.section, u.line, incipit(u.text), what))

    # lead-ins
    import os
    leadins = os.path.join(os.path.dirname(os.path.abspath(ledger_path)),
                           "leadins.txt")
    if os.path.exists(leadins):
        wanted = {}
        for line in open(leadins, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line:
                continue
            echoed = line.startswith("!")
            text = line[1:] if echoed else line
            n, e = wanted.get(text, (0, False))
            wanted[text] = (n + 1, e or echoed)
        for text, (n, echoed) in wanted.items():
            have = new_text.count("**%s**" % text)
            if have < n:
                fail("lead-in gone%s: **%s** (%d of %d left)" % (
                    " (echoed elsewhere)" if echoed else "", text, have, n))
    else:
        fail("no leadins.txt beside the ledger")

    if budget:
        counts = section_words(new_text)
        for sec, cap in sorted(BUDGET.items()):
            n = counts.get(sec, 0)
            if n > cap:
                fail("§%d: %d words, budget %d" % (sec, n, cap))

    for msg in fails:
        print(msg)
    old_t = keyword_totals(base_units)
    new_t = keyword_totals(doc.units)
    print("key words, old -> new: " + ", ".join(
        "%s %d -> %d" % (k, old_t[k], new_t[k]) for k in KW_RANK))
    oc = section_words(open(base_path, encoding="utf-8").read())
    nc = section_words(new_text)
    print("words, old -> new: " + ", ".join(
        "§%d %d -> %d" % (s, oc.get(s, 0), nc.get(s, 0))
        for s in sorted(set(oc) | set(nc))) +
        ", total %d -> %d" % (sum(oc.values()), sum(nc.values())))
    print("%d failure(s)" % len(fails))
    return 1 if fails else 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "split" and len(argv) == 2:
        split(argv[1])
        return 0
    if len(argv) >= 4 and argv[0] == "check":
        rest = [a for a in argv[1:] if a != "--budget"]
        if len(rest) != 3:
            raise SystemExit(__doc__)
        return check(rest[0], rest[1], rest[2], "--budget" in argv)
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
