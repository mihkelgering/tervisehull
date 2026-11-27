#!/usr/bin/env python3
"""Generate db/init/006_md_workbook_import.sql from the MD interaction workbook.

Usage (from the repository root; the workbook is untrusted data, so run the
interpreter in isolated mode from outside the folder that holds it):

    python3 -I db/tools/import_md_workbook.py /path/to/medical-doctor-input.xlsx

Reads, with the standard library only:
  * the workbook's CICILY_MD_INTERACTION_V2 tabs (summary block, Cases table,
    Evidence table);
  * db/init/002_seed_smoke_data.sql for the concept catalog and aliases;
  * db/tools/md_workbook_overrides.json for every hand-reviewed decision.

Writes:
  * db/init/006_md_workbook_import.sql  (one transaction; regenerate, don't edit)
  * db/tools/md_workbook_concept_map.csv (every factor name -> concept, reviewable)

Fails loudly when a factor name cannot be resolved, when a resolution would
silently pick a combined seed concept, or when an override does not match the
workbook. Nothing in the output is publishable: every imported row keeps a
non-public status and the 'review' risk level.
"""
from __future__ import annotations

import csv
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import OrderedDict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SEED_SQL = REPO / "db" / "init" / "002_seed_smoke_data.sql"
OVERRIDES = REPO / "db" / "tools" / "md_workbook_overrides.json"
OUT_SQL = REPO / "db" / "init" / "006_md_workbook_import.sql"
OUT_MAP = REPO / "db" / "tools" / "md_workbook_concept_map.csv"

TEMPLATE_MARK = "CICILY_MD_INTERACTION_V2"
TIMING_SHEETS = {"Tühja kõhuga", "Päevaaeg"}
NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}

# ID ranges used by this file (the seed stops well below each of them).
ID_TOPIC_TEXT = 700000       # + topic_no * 10 + slot
ID_RULE_TEXT = 710000        # + rule_no * 10 + slot
ID_CONCEPT_TEXT = 730000     # + n
ID_CONCEPT = 6000            # + n
ID_ALIAS = 1000              # + n
ID_RELATIONSHIP = 6100       # + n
ID_SOURCE = 30000            # + n
ID_RULE = 40000              # + n
ID_PARTICIPANT = 41000       # + n
ID_TIMING = 43000            # + n

GROUP_TYPES = {"drug_group", "supplement_group"}
# Seed display names that are lists or pairs of things: never a silent match.
COMBINED_NAME = re.compile(r"(/|,|;| ja |: | jt\b|\bsh\b)")

LOCALE_ET = "(SELECT id FROM locales WHERE code = 'et')"
RISK_REVIEW = "(SELECT id FROM risk_levels WHERE code = 'review')"


def die(msg: str) -> None:
    sys.stderr.write(f"error: {msg}\n")
    sys.exit(1)


class ResolutionError(Exception):
    pass


# ---------------------------------------------------------------------------
# Workbook
# ---------------------------------------------------------------------------
def col_of(ref: str) -> str:
    return re.match(r"[A-Z]+", ref).group(0)


def row_of(ref: str) -> int:
    return int(re.search(r"\d+", ref).group(0))


def read_workbook(path: Path) -> "OrderedDict[str, dict[int, dict[str, str]]]":
    z = zipfile.ZipFile(path)
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    targets = {r.get("Id"): r.get("Target") for r in rels}
    shared: list[str] = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
            shared.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
    sheets: "OrderedDict[str, dict[int, dict[str, str]]]" = OrderedDict()
    for s in wb.find("m:sheets", NS):
        name = s.get("name")
        target = targets[s.get("{%s}id" % NS["r"])].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        root = ET.fromstring(z.read(target))
        rows: dict[int, dict[str, str]] = {}
        for c in root.iter("{%s}c" % NS["m"]):
            ref = c.get("r")
            t = c.get("t")
            v = c.find("m:v", NS)
            f = c.find("m:f", NS)
            val = None
            if t == "s" and v is not None:
                val = shared[int(v.text)]
            elif t == "inlineStr":
                val = "".join(x.text or "" for x in c.iter("{%s}t" % NS["m"]))
            elif v is not None:
                val = v.text
            d = rows.setdefault(row_of(ref), {})
            if val not in (None, ""):
                d[col_of(ref)] = val
            if f is not None and f.text:
                d[col_of(ref) + "_f"] = f.text
        sheets[name] = rows
    return sheets


def clean(text: str | None) -> str | None:
    if text is None:
        return None
    t = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    return t or None


def parse_topics(sheets) -> list[dict]:
    topics = []
    for name, rows in sheets.items():
        if rows.get(1, {}).get("J") != TEMPLATE_MARK:
            continue

        def cell(r, c):
            return clean(rows.get(r, {}).get(c))

        if not cell(4, "B"):
            continue  # the empty "New interaction" template
        nums = sorted(rows)
        case_hdr = next(n for n in nums if rows[n].get("A") == "Case name")
        ev_title = next(n for n in nums if n > case_hdr and (rows[n].get("A") or "").startswith("Evidence"))
        ev_hdr = next(n for n in nums if n > ev_title and rows[n].get("A") == "DOI / source")
        topic = {
            "sheet": name, "title": cell(4, "B"), "factor_1": cell(7, "B"), "factor_2": cell(7, "E"),
            "what_happens": cell(11, "B"), "proposed_guidance": cell(15, "B"), "when_applies": cell(19, "B"),
            "open_questions": cell(23, "B"), "handoff": cell(27, "B"), "author": cell(27, "E"),
            "relation": cell(29, "B"), "risk": cell(30, "B"), "other_factors": cell(31, "B"), "notes": cell(34, "B"),
            "cases": [], "evidence": [],
        }
        for n in range(case_hdr + 1, ev_title):
            d = rows.get(n, {})
            if clean(d.get("A")):
                topic["cases"].append({
                    "row": n, "name": clean(d.get("A")), "factor_1": clean(d.get("B")), "factor_2": clean(d.get("C")),
                    "scope": clean(d.get("D")), "conditions": clean(d.get("E")), "conclusion": clean(d.get("F")),
                    "risk_override": clean(d.get("G")), "risk_used": clean(d.get("H")),
                })
        for n in range(ev_hdr + 1, nums[-1] + 1):
            d = rows.get(n, {})
            if clean(d.get("A")) or clean(d.get("C")):
                topic["evidence"].append({
                    "row": n, "source": clean(d.get("A")), "formula": d.get("A_f"), "applies": clean(d.get("B")),
                    "finding": clean(d.get("C")), "limitations": clean(d.get("D")), "locator": clean(d.get("E")),
                    "guidance": clean(d.get("F")),
                })
        topics.append(topic)
    return topics


# ---------------------------------------------------------------------------
# Seed catalog (concepts, aliases, relationships) from 002
# ---------------------------------------------------------------------------
def sql_rows(block: str):
    """Yield the tuples of an INSERT ... VALUES block as lists of Python values."""
    body = block.split("VALUES", 1)[1]
    pos = 0
    n = len(body)
    while pos < n:
        start = body.find("(", pos)
        if start < 0:
            break
        i = start + 1
        vals: list = []
        cur = ""
        in_str = False
        depth = 0  # parentheses inside a value, e.g. now()
        while i < n:
            ch = body[i]
            if in_str:
                if ch == "'":
                    if i + 1 < n and body[i + 1] == "'":
                        cur += "'"
                        i += 2
                        continue
                    in_str = False
                    vals.append(("str", cur))
                    cur = ""
                else:
                    cur += ch
            else:
                if ch == "'":
                    in_str = True
                    cur = ""
                elif ch == "(":
                    depth += 1
                    cur += ch
                elif ch == ")" and depth > 0:
                    depth -= 1
                    cur += ch
                elif ch == ",":
                    if cur.strip():
                        vals.append(("raw", cur.strip()))
                    cur = ""
                elif ch == ")":
                    if cur.strip():
                        vals.append(("raw", cur.strip()))
                    break
                else:
                    cur += ch
            i += 1
        yield [v[1] if v[0] == "str" else (None if v[1] == "NULL" else v[1]) for v in vals]
        pos = i + 1


def read_seed(path: Path) -> dict:
    src = path.read_text(encoding="utf-8")

    def block(table: str) -> str:
        m = re.search(r"^INSERT INTO %s \(([^)]*)\)\s*VALUES\s*(.*?);\s*$" % table, src, re.S | re.M)
        if not m:
            die(f"seed: INSERT INTO {table} block not found in {path}")
        return m.group(0)

    translations = {}
    for row in sql_rows(block("translations")):
        translations[(int(row[0]), int(row[1]))] = row[2]
    concepts: "OrderedDict[str, dict]" = OrderedDict()
    for row in sql_rows(block("health_concepts")):
        cid, public_id, text_id, ctype, ccat = int(row[0]), row[1], int(row[2]), row[3], row[4]
        concepts[public_id] = {
            "id": cid, "public_id": public_id, "name": translations[(text_id, 1)],
            "type": ctype, "category": ccat, "seed": True,
            "combined": bool(COMBINED_NAME.search(translations[(text_id, 1)])),
        }
    aliases = []
    for row in sql_rows(block("concept_aliases")):
        aliases.append({"id": int(row[0]), "concept_id": int(row[1]), "alias": row[2], "locale_id": int(row[4])})
    relationships = set()
    for row in sql_rows(block("concept_relationships")):
        relationships.add((int(row[1]), int(row[2]), row[3]))
    return {"concepts": concepts, "aliases": aliases, "relationships": relationships}


# ---------------------------------------------------------------------------
# Concept resolution
# ---------------------------------------------------------------------------
class Catalog:
    def __init__(self, seed: dict, overrides: dict):
        self.concepts: "OrderedDict[str, dict]" = seed["concepts"]
        self.by_id = {c["id"]: c for c in self.concepts.values()}
        self.aliases = seed["aliases"]
        self.relationships = set(seed["relationships"])
        self.overrides = {k.strip().lower(): v for k, v in overrides["concepts"].items()}
        self.new_concepts: list[dict] = []
        self.new_aliases: list[dict] = []          # {concept_public_id, alias}
        self.alias_moves: list[dict] = []          # {alias_id, from, to, alias}
        self.alias_rejects: list[dict] = []        # {alias_id, concept, alias, note}
        self.new_relationships: list[tuple] = []   # (from_public_id, to_public_id, type, note)
        self.retypes: list[dict] = []
        self.map_rows: "OrderedDict[str, dict]" = OrderedDict()
        self.next_concept = 0
        self._define_new(overrides)
        self._apply_retypes(overrides.get("retype", {}))
        self._reject_aliases(overrides.get("reject_aliases", []))

    # -- definitions ---------------------------------------------------------
    def _define_new(self, overrides: dict) -> None:
        # New concepts and formulations first, so 'existing' entries may refer to them.
        for key, spec in overrides["concepts"].items():
            if "new" in spec:
                self._add_concept(spec["new"], spec.get("name") or key, spec["type"], spec["category"],
                                  spec.get("aliases", []), note=spec.get("note"), workbook_name=key)
        for key, spec in overrides["concepts"].items():
            if "formulation" in spec:
                self._add_concept(spec["formulation"], spec.get("name") or key, "formulation", "drug", [],
                                  dosage_form=spec.get("dosage_form"), route=spec.get("route"),
                                  strength_text=spec.get("strength_text"), note=spec.get("note"), workbook_name=key)
                self._relate(spec["formulation"], spec["of"], "is_a", "Formulation of its active substance (MD workbook import).")
        for key, spec in overrides["concepts"].items():
            if "new" in spec:
                if spec.get("is_a"):
                    self._relate(spec["new"], spec["is_a"], "is_a", "Group membership from the MD workbook import.")
                if spec.get("narrower_than"):
                    self._relate(spec["new"], spec["narrower_than"], "narrower_than",
                                 "Split from a combined seed concept by the MD workbook import.")

    def _add_concept(self, public_id, name, ctype, ccat, extra_aliases, dosage_form=None, route=None,
                     strength_text=None, note=None, workbook_name=None) -> None:
        if public_id in self.concepts:
            die(f"override: public_id {public_id} already exists")
        self.next_concept += 1
        c = {
            "id": ID_CONCEPT + self.next_concept, "public_id": public_id, "name": name, "type": ctype,
            "category": ccat, "seed": False, "combined": False, "dosage_form": dosage_form, "route": route,
            "strength_text": strength_text, "text_id": ID_CONCEPT_TEXT + self.next_concept, "note": note,
        }
        if ctype == "formulation" and not (dosage_form or route or strength_text):
            die(f"override: formulation {public_id} needs dosage_form, route or strength_text")
        self.concepts[public_id] = c
        self.by_id[c["id"]] = c
        self.new_concepts.append(c)
        # The display name itself and the workbook spelling become candidate aliases;
        # a seed alias with the same text on another concept is re-pointed here.
        wanted = [name] + [a for a in extra_aliases]
        if workbook_name and "::" not in workbook_name and workbook_name.lower() != name.lower():
            wanted.append(workbook_name)
        for a in wanted:
            self._alias_to(public_id, a)

    def _alias_to(self, public_id: str, alias: str) -> None:
        concept = self.concepts[public_id]
        moved = False
        for row in self.aliases:
            if row["alias"].lower() == alias.lower() and row["concept_id"] != concept["id"] \
                    and not any(m["alias_id"] == row["id"] for m in self.alias_moves) \
                    and not any(r["alias_id"] == row["id"] for r in self.alias_rejects):
                if concept["seed"]:
                    continue  # a seed concept keeps whatever the seed says; explicit rejects handle the wrong ones
                if not moved and not self._has_alias(concept, row["alias"]):
                    self.alias_moves.append({"alias_id": row["id"], "from": self.by_id[row["concept_id"]]["public_id"],
                                             "to": public_id, "alias": row["alias"]})
                    row["concept_id"] = concept["id"]
                    moved = True
                else:
                    # The name now has a concept of its own; a second seed row with the
                    # same text on another concept is a duplicate pointing elsewhere.
                    self.alias_rejects.append({"alias_id": row["id"], "concept": self.by_id[row["concept_id"]]["public_id"],
                                               "alias": row["alias"], "note": f"{alias!r} now has its own concept {public_id}"})
        if moved or self._has_alias(concept, alias):
            return
        if any(n["concept"] == public_id and n["alias"].lower() == alias.lower() for n in self.new_aliases):
            return
        self.new_aliases.append({"concept": public_id, "alias": alias})

    def _has_alias(self, concept: dict, alias: str) -> bool:
        return any(r["concept_id"] == concept["id"] and r["alias"].lower() == alias.lower() for r in self.aliases)

    def _relate(self, from_pid: str, to_pid: str, rtype: str, note: str) -> None:
        if to_pid not in self.concepts:
            die(f"override: relationship target {to_pid} does not exist")
        key = (self.concepts[from_pid]["id"], self.concepts[to_pid]["id"], rtype)
        if key in self.relationships:
            return
        self.relationships.add(key)
        self.new_relationships.append((from_pid, to_pid, rtype, note))

    def _apply_retypes(self, retypes: dict) -> None:
        for pid, spec in retypes.items():
            if pid not in self.concepts or not self.concepts[pid]["seed"]:
                die(f"retype: {pid} is not a seed concept")
            c = self.concepts[pid]
            self.retypes.append({"public_id": pid, "name": c["name"], "from_type": c["type"], "from_category": c["category"],
                                 "type": spec["type"], "category": spec["category"], "note": spec.get("note")})
            c["type"], c["category"] = spec["type"], spec["category"]

    def _reject_aliases(self, rejects: list) -> None:
        for r in rejects:
            concept = self.concepts.get(r["concept"])
            if concept is None:
                die(f"reject_aliases: {r['concept']} does not exist")
            rows = [a for a in self.aliases if a["concept_id"] == concept["id"] and a["alias"].lower() == r["alias"].lower()]
            if not rows:
                die(f"reject_aliases: no alias {r['alias']!r} on {r['concept']}")
            for a in rows:
                if any(x["alias_id"] == a["id"] for x in self.alias_rejects):
                    continue  # already rejected because the name got its own concept
                self.alias_rejects.append({"alias_id": a["id"], "concept": r["concept"], "alias": a["alias"], "note": r.get("note")})

    # -- resolution ----------------------------------------------------------
    def resolve(self, name: str, sheet: str) -> list[dict]:
        """Return the participant concepts for a workbook factor name (several = alternatives)."""
        key = name.strip().lower()
        spec = self.overrides.get(f"{sheet}::{name}".lower()) or self.overrides.get(key)
        if spec is not None and "alternatives" in spec:
            members = []
            for m in spec["alternatives"]:
                r = self.resolve(m, sheet)
                if len(r) != 1:
                    raise ResolutionError(f"alternatives member {m!r} must resolve to one concept")
                members.append(r[0])
                for row in self.map_rows.values():
                    if row["factor_name"].lower() == m.lower() and r[0]["public_id"] in row["public_ids"]:
                        row["member_of"] = name
            self._map(name, sheet, "alternatives", [c["public_id"] for c in members], "override",
                      spec.get("note") or "Any one of the listed members.")
            return members
        if spec is not None:
            pid = spec.get("existing") or spec.get("new") or spec.get("formulation")
            if pid not in self.concepts:
                raise ResolutionError(f"override for {name!r} points at unknown concept {pid}")
            c = self.concepts[pid]
            how = "override"
            if "existing" in spec and spec.get("alias", True) and c["seed"]:
                self._alias_to(pid, name)
            elif "existing" in spec and spec.get("alias", True):
                self._alias_to(pid, name)
            kind = "existing" if "existing" in spec else ("formulation" if "formulation" in spec else "new")
            if kind == "existing" and not c["seed"]:
                kind = "new (shared)"
            self._map(name, sheet, kind, [pid], how, spec.get("note"))
            return [c]
        # Exact display name (case-insensitive).
        exact = [c for c in self.concepts.values() if c["name"].lower() == key]
        if len(exact) == 1 and not exact[0]["combined"]:
            self._map(name, sheet, "existing", [exact[0]["public_id"]], "exact", None)
            return exact
        if len(exact) > 1:
            raise ResolutionError(f"{name!r} matches several concepts by name ({[c['public_id'] for c in exact]}); add an override")
        if exact and exact[0]["combined"]:
            raise ResolutionError(f"{name!r} matches the combined seed concept {exact[0]['public_id']} by name; add an override")
        # Alias.
        hits = [self.by_id[a["concept_id"]] for a in self.aliases if a["alias"].lower() == key]
        hits = list({c["public_id"]: c for c in hits}.values())
        usable = [c for c in hits if not c["combined"]]
        if len(usable) == 1 and len(hits) == 1:
            self._map(name, sheet, "existing", [usable[0]["public_id"]], "alias", None)
            return usable
        if hits:
            raise ResolutionError(f"{name!r} only matches by alias on {[c['public_id'] + ' ' + c['name'] for c in hits]}"
                " (combined or ambiguous); add an override that splits or picks")
        raise ResolutionError(f"unresolved factor name {name!r} on sheet {sheet!r}; add an override")

    def _map(self, name, sheet, kind, public_ids, how, note):
        # One map row per (name, resolution); a name resolved per sheet gets a row per target.
        key = name.lower()
        row = self.map_rows.get(key)
        if row is not None and (row["resolution"] != kind or row["public_ids"] != public_ids):
            key = f"{name}::{';'.join(public_ids)}".lower()
            row = self.map_rows.get(key)
        if row is None:
            row = self.map_rows[key] = {
                "factor_name": name, "sheets": [], "resolution": kind, "public_ids": public_ids, "how": how,
                "note": note or "", "member_of": "",
            }
        if sheet not in row["sheets"]:
            row["sheets"].append(sheet)


# ---------------------------------------------------------------------------
# Evidence sources
# ---------------------------------------------------------------------------
DOI_RE = re.compile(r"\b(10\.\d{4,9}/[^\s,;\"')]+)")


def classify_source(text: str, formula: str | None) -> dict:
    url = None
    if formula:
        m = re.match(r'HYPERLINK\("([^"]+)"', formula)
        if m:
            url = m.group(1)
    doi = None
    if re.fullmatch(r"10\.\d{4,9}/\S+", text):
        doi = text
    else:
        m = DOI_RE.search(text)
        if m:
            doi = m.group(1).rstrip(".")
    if doi and not url:
        url = "https://doi.org/" + doi
    pmid = pmcid = None
    if url:
        m = re.search(r"pubmed\.ncbi\.nlm\.nih\.gov/(\d+)", url)
        if m:
            pmid = m.group(1)
        m = re.search(r"pmc\.ncbi\.nlm\.nih\.gov/articles/(PMC\d+)", url)
        if m:
            pmcid = m.group(1)
    host = re.sub(r"^https?://(www\.)?", "", url or "").split("/")[0]
    path = (url or "").lower()
    if pmid:
        stype, grade = "pubmed", "unknown"
    elif pmcid:
        stype, grade = "pmc", "unknown"
    elif host.endswith("medicines.org.uk"):
        stype, grade = ("pil", "label") if ("/pil" in path or "pil." in path) else ("spc", "label")
    elif host.endswith("dailymed.nlm.nih.gov") or host.endswith("accessdata.fda.gov"):
        stype, grade = "label", "label"
    elif host.endswith("fda.gov"):
        stype, grade = "guideline", "guideline"
    elif host.endswith("ema.europa.eu"):
        stype, grade = "ema", "label"
    elif host.endswith("nhs.uk"):
        stype, grade = "guideline", "guideline"
    else:
        stype, grade = "other", "unknown"
    year = None
    if doi != text:
        years = sorted({int(y) for y in re.findall(r"\b((?:19|20)\d\d)\b", text)})
        if len(years) == 1:
            year = years[0]
    if doi:
        key = ("doi", doi.lower())
    elif pmid:
        key = ("pmid", pmid)
    elif pmcid:
        key = ("pmcid", pmcid)
    elif url:
        key = ("url", url.lower())
    else:
        key = ("text", text.lower())
    role = "safety_label" if stype in ("spc", "pil", "label", "ema") else ("background" if stype == "guideline" else "primary_support")
    return {"key": key, "title": text, "url": url, "doi": doi, "pmid": pmid, "pmcid": pmcid, "source_type": stype,
            "evidence_grade": grade, "publication_year": year, "evidence_role": role,
            "study_design": "label" if grade == "label" else None}


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------
LABELS = ("Juhis", "Olulisus", "Arvuline mõju", "Arvuline tulemus", "Nõude tugevus", "Ajastuse tugevus")


def split_labelled(text: str | None) -> dict:
    """Split a conclusion cell into its labelled parts ("Olulisus: ...")."""
    parts: dict[str, list[str]] = {"": []}
    current = ""
    for line in (text or "").split("\n"):
        m = re.match(r"^(%s):\s*(.*)$" % "|".join(re.escape(l) for l in LABELS), line)
        if m:
            current = m.group(1)
            parts.setdefault(current, []).append(m.group(2))
        else:
            parts.setdefault(current, []).append(line)
    return {k: clean("\n".join(v)) for k, v in parts.items()}


def q(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def concept_ref(pid: str) -> str:
    return f"(SELECT id FROM health_concepts WHERE public_id = {q(pid)})"


RELATION_MAP = {"Single pair": "single_pair", "Any one of these": "any_member_of_group",
                "All factors together": "all_factors_together", "Related cases below": "related_cases",
                "To clarify": "to_clarify"}
HANDOFF_MAP = {"Working draft": "working_draft", "Ready for team review": "ready_for_team_review"}
PAIR_TYPES = {
    frozenset(["drug"]): "drug_drug", frozenset(["drug", "food_drink"]): "drug_food",
    frozenset(["drug", "supplement"]): "drug_supplement", frozenset(["drug", "lifestyle"]): "drug_lifestyle",
    frozenset(["drug", "condition"]): "drug_condition", frozenset(["supplement", "food_drink"]): "supplement_food",
    frozenset(["supplement"]): "supplement_supplement", frozenset(["food_drink"]): "food_food",
}


def interaction_type(side1: list[dict], side2: list[dict]) -> str:
    cats = frozenset(c["category"] for c in side1 + side2)
    return PAIR_TYPES.get(cats, "general_factor")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main(argv: list[str]) -> None:
    if len(argv) != 2:
        die("usage: python3 -I db/tools/import_md_workbook.py <workbook.xlsx>")
    xlsx = Path(argv[1])
    if not xlsx.is_file():
        die(f"{xlsx} is not a file")
    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    topics = parse_topics(read_workbook(xlsx))
    if not topics:
        die("no CICILY_MD_INTERACTION_V2 tabs with content found")
    catalog = Catalog(read_seed(SEED_SQL), overrides)
    timing_specs = {k.lower(): v for k, v in overrides.get("timing", {}).items()}
    effect_specs = overrides.get("evidence_effects", {})

    out: list[str] = []
    w = out.append
    w("-- Generated by db/tools/import_md_workbook.py from the MD interaction workbook")
    w(f"-- ({xlsx.name}). Do not edit by hand: change db/tools/md_workbook_overrides.json")
    w("-- or the workbook and regenerate. See db/README.md.")
    w("--")
    w("-- Everything imported here stays unpublishable: rules carry the 'review' risk")
    w("-- level, medical_review_status 'not_started' and publication_status 'draft';")
    w("-- new concepts are 'draft'; sources are 'imported'; findings are 'draft'.")
    w("-- Display text is Estonian only (locale et); no English is invented.")
    w("")
    w("BEGIN;")
    w("")

    # ---- catalog changes --------------------------------------------------
    # Resolve every factor first so alias moves/additions are complete.
    resolved_cases = []
    problems: list[str] = []
    for ti, t in enumerate(topics, 1):
        for c in t["cases"]:
            try:
                side1 = catalog.resolve(c["factor_1"], t["sheet"])
                side2 = [] if t["sheet"] in TIMING_SHEETS else catalog.resolve(c["factor_2"], t["sheet"])
            except ResolutionError as exc:
                problems.append(str(exc))
                continue
            resolved_cases.append((ti, t, c, side1, side2))
    if problems:
        for pmsg in sorted(set(problems)):
            sys.stderr.write(f"error: {pmsg}\n")
        die(f"{len(set(problems))} factor name(s) unresolved; add overrides to {OVERRIDES.relative_to(REPO)}")

    w("-- ---------------------------------------------------------------------------")
    w("-- Catalog: retyped seed concepts, rejected aliases, new concepts (draft),")
    w("-- re-pointed and added aliases, relationships. Reviewable list:")
    w("-- db/tools/md_workbook_concept_map.csv.")
    w("-- ---------------------------------------------------------------------------")
    for r in catalog.retypes:
        w(f"UPDATE health_concepts SET concept_type = {q(r['type'])}, concept_category = {q(r['category'])}"
          f" WHERE public_id = {q(r['public_id'])};  -- was {r['from_type']}/{r['from_category']}: {r['note'] or ''}")
    for r in catalog.alias_rejects:
        w(f"UPDATE concept_aliases SET status = 'rejected' WHERE id = {r['alias_id']};  -- {r['concept']} {r['alias']!r}: {r['note'] or ''}")
    w("")
    if catalog.new_concepts:
        w("INSERT INTO translation_keys (id, key)")
        w("VALUES")
        w(",\n".join(f"  ({c['text_id']}, {q('concept.' + c['public_id'] + '.display_name')})" for c in catalog.new_concepts) + ";")
        w("")
        w("INSERT INTO translations (text_id, locale_id, text)")
        w("VALUES")
        w(",\n".join(f"  ({c['text_id']}, {LOCALE_ET}, {q(c['name'])})" for c in catalog.new_concepts) + ";")
        w("")
        w("INSERT INTO health_concepts (id, public_id, display_name_text_id, concept_type, concept_category, status, review_status, can_trigger_matching, dosage_form, route, strength_text)")
        w("VALUES")
        w(",\n".join(
            f"  ({c['id']}, {q(c['public_id'])}, {c['text_id']}, {q(c['type'])}, {q(c['category'])}, 'draft', 'not_started', true, "
            f"{q(c['dosage_form'])}, {q(c['route'])}, {q(c['strength_text'])})" for c in catalog.new_concepts) + ";")
        w("")
    for m in catalog.alias_moves:
        w(f"UPDATE concept_aliases SET concept_id = {concept_ref(m['to'])} WHERE id = {m['alias_id']};  -- {m['alias']!r}: {m['from']} -> {m['to']}")
    if catalog.new_aliases:
        w("")
        w("INSERT INTO concept_aliases (id, concept_id, alias, alias_type, locale_id, status, search_priority)")
        w("VALUES")
        w(",\n".join(f"  ({ID_ALIAS + i}, {concept_ref(a['concept'])}, {q(a['alias'])}, 'synonym', {LOCALE_ET}, 'candidate', 10)"
                     for i, a in enumerate(catalog.new_aliases, 1)) + ";")
    if catalog.new_relationships:
        w("")
        w("INSERT INTO concept_relationships (id, from_concept_id, to_concept_id, relationship_type, status, review_note)")
        w("VALUES")
        w(",\n".join(f"  ({ID_RELATIONSHIP + i}, {concept_ref(f)}, {concept_ref(t)}, {q(rt)}, 'draft', {q(note)})"
                     for i, (f, t, rt, note) in enumerate(catalog.new_relationships, 1)) + ";")
    w("")

    # ---- evidence sources -------------------------------------------------
    sources: "OrderedDict[tuple, dict]" = OrderedDict()
    for t in topics:
        for e in t["evidence"]:
            if not e["source"]:
                die(f"evidence row {t['sheet']}:{e['row']} has no source")
            info = classify_source(e["source"], e["formula"])
            if info["key"] not in sources:
                info["public_id"] = f"SRC_{len(sources) + 1:04d}"
                info["id"] = ID_SOURCE + len(sources) + 1
                sources[info["key"]] = info
            else:
                # Same DOI/PMID/URL cited twice: keep the fuller citation as the title
                # and fill identifiers the first citation lacked.
                kept = sources[info["key"]]
                if len(info["title"]) > len(kept["title"]):
                    kept["title"], kept["publication_year"] = info["title"], info["publication_year"] or kept["publication_year"]
                for f in ("url", "doi", "pmid", "pmcid"):
                    kept[f] = kept[f] or info[f]
            e["source_info"] = sources[info["key"]]
    w("-- ---------------------------------------------------------------------------")
    w("-- Evidence sources: one row per distinct DOI / PMID / PMCID / URL, as cited.")
    w("-- Titles are the citation text as written (the workbook gives no other title).")
    w("-- ---------------------------------------------------------------------------")
    w("INSERT INTO evidence_sources (id, public_id, title, source_type, url, pmid, pmcid, doi, publication_year, evidence_grade, verification_status)")
    w("VALUES")
    w(",\n".join(
        f"  ({s['id']}, {q(s['public_id'])}, {q(s['title'])}, {q(s['source_type'])}, {q(s['url'])}, {q(s['pmid'])}, {q(s['pmcid'])}, "
        f"{q(s['doi'])}, {q(s['publication_year'])}, {q(s['evidence_grade'])}, 'imported')" for s in sources.values()) + ";")
    w("")

    # ---- topics -----------------------------------------------------------
    w("-- ---------------------------------------------------------------------------")
    w("-- Topics: one per workbook tab.")
    w("-- ---------------------------------------------------------------------------")
    topic_text_slots = [("title", 1), ("what_happens", 2), ("proposed_guidance", 3), ("when_applies", 4),
                        ("open_questions", 5), ("notes", 6), ("factor_1", 7), ("factor_2", 8), ("other_factors", 9)]
    keys, texts, topic_rows = [], [], []
    for ti, t in enumerate(topics, 1):
        t["public_id"] = f"TOPIC_{ti:04d}"
        ids = {}
        for field, slot in topic_text_slots:
            if t[field]:
                tid = ID_TOPIC_TEXT + ti * 10 + slot
                ids[field] = tid
                keys.append(f"  ({tid}, {q('topic.' + t['public_id'] + '.' + field)})")
                texts.append(f"  ({tid}, {LOCALE_ET}, {q(t[field])})")
        relation = RELATION_MAP.get(t["relation"] or "", "to_clarify")
        handoff = HANDOFF_MAP.get(t["handoff"] or "", "working_draft")
        if (t["risk"] or "Not assessed") != "Not assessed":
            die(f"topic {t['sheet']!r} has an assessed risk {t['risk']!r}; map it before importing")
        topic_rows.append(
            f"  ({ti}, {q(t['public_id'])}, {ids['title']}, {q(ids.get('what_happens'))}, {q(ids.get('proposed_guidance'))}, "
            f"{q(ids.get('when_applies'))}, {q(ids.get('open_questions'))}, {q(ids.get('notes'))}, {q(ids.get('factor_1'))}, "
            f"{q(ids.get('factor_2'))}, {q(ids.get('other_factors'))}, {RISK_REVIEW}, {q(relation)}, {q(handoff)}, "
            f"{q(t['author'])}, {q(t['sheet'])})")
    w("INSERT INTO translation_keys (id, key)")
    w("VALUES")
    w(",\n".join(keys) + ";")
    w("")
    w("INSERT INTO translations (text_id, locale_id, text)")
    w("VALUES")
    w(",\n".join(texts) + ";")
    w("")
    w("INSERT INTO interaction_topics (id, public_id, title_text_id, what_happens_text_id, proposed_guidance_text_id, when_applies_text_id, open_questions_text_id, notes_text_id, factor_1_text_id, factor_2_text_id, other_factors_text_id, default_risk_level_id, factor_relation, handoff_status, author_name, source_workbook_sheet)")
    w("VALUES")
    w(",\n".join(topic_rows) + ";")
    w("")

    # ---- rules ------------------------------------------------------------
    w("-- ---------------------------------------------------------------------------")
    w("-- Rules: one per workbook case. Text columns hold the MD's cells as written;")
    w("-- significance / numeric effect are the labelled parts of the conclusion cell.")
    w("-- ---------------------------------------------------------------------------")
    keys, texts, rule_rows, participant_rows, timing_rows, audit_rows = [], [], [], [], [], []
    rule_by_case: dict[tuple, dict] = {}
    n_participants = 0
    n_timing = 0
    for ri, (ti, t, c, side1, side2) in enumerate(resolved_cases, 1):
        rid = ID_RULE + ri
        pid = f"RULE_{ri:04d}"
        parts = split_labelled(c["conclusion"])
        significance = parts.get("Olulisus")
        numeric = clean("\n".join(x for x in (parts.get("Arvuline mõju"), parts.get("Arvuline tulemus")) if x))
        texts_for_rule = [("title", 1, c["name"]), ("scope_note", 2, c["scope"]), ("conditions", 3, c["conditions"]),
                          ("clinical_conclusion", 4, c["conclusion"]), ("significance", 5, significance),
                          ("numeric_effect", 6, numeric)]
        is_timing = t["sheet"] in TIMING_SHEETS
        instruction = None
        if is_timing:
            instruction = parts.get("Juhis") or parts.get("")
            if not instruction:
                die(f"timing case {c['name']!r} has no instruction text")
            texts_for_rule.append(("timing_instruction", 7, instruction))
        ids = {}
        for field, slot, text in texts_for_rule:
            if text:
                tid = ID_RULE_TEXT + ri * 10 + slot
                ids[field] = tid
                keys.append(f"  ({tid}, {q('rule.' + pid + '.' + field)})")
                texts.append(f"  ({tid}, {LOCALE_ET}, {q(text)})")
        if c["risk_override"]:
            die(f"case {c['name']!r} has a risk override {c['risk_override']!r}; map it before importing")
        itype = "drug_administration" if is_timing else interaction_type(side1, side2)
        scope = "timing_context" if is_timing else "general_interaction"
        rule_rows.append(
            f"  ({rid}, {q(pid)}, {ids['title']}, {q(itype)}, {q(scope)}, {RISK_REVIEW}, 'not_started', 'draft', 1, {ti}, true, "
            f"{q(ids.get('scope_note'))}, {q(ids.get('conditions'))}, {q(ids.get('clinical_conclusion'))}, "
            f"{q(ids.get('significance'))}, {q(ids.get('numeric_effect'))}, {q(t['sheet'])}, {q(c['name'])})")
        rule_by_case[(t["sheet"], c["name"].lower())] = {"id": rid, "public_id": pid, "links": OrderedDict()}
        for role, side in (("primary", side1), ("interacting_factor", side2)):
            group = 1 if len(side) > 1 else None
            alt_no = {"primary": 1, "interacting_factor": 2}[role]
            for concept in side:
                n_participants += 1
                scope_match = "include_descendants" if concept["type"] in GROUP_TYPES else "exact_concept"
                participant_rows.append(
                    f"  ({ID_PARTICIPANT + n_participants}, {rid}, {concept_ref(concept['public_id'])}, {q(role)}, "
                    f"{q(scope_match)}, true, {q(alt_no if group else None)})")
        if is_timing:
            spec = timing_specs.get(f"{t['sheet']}::{c['name']}".lower())
            rows = spec["rows"] if spec else [{}]
            ttype = spec["timing_type"] if spec else ("take_on_empty_stomach" if t["sheet"] == "Tühja kõhuga" else "take_at_time_of_day")
            for r in rows:
                n_timing += 1
                timing_rows.append(
                    f"  ({ID_TIMING + n_timing}, {rid}, {q(ttype)}, {ids['timing_instruction']}, 'draft', {q(r.get('anchor'))}, "
                    f"{q(r.get('relation'))}, {q(r.get('min_minutes'))}, {q(r.get('max_minutes'))}, {q(r.get('alternative_group'))}, "
                    f"{q(r.get('time_of_day'))}, {q(r.get('stay_upright_minutes'))}, {q(r.get('with_water_ml_min'))}, "
                    f"{q(r.get('with_water_ml_max'))}, {q(r.get('requirement_strength'))})")
        audit_rows.append(f"  ('interaction_rule', {rid}, 'import', {q(json.dumps({'public_id': pid, 'sheet': t['sheet'], 'case': c['name']}, ensure_ascii=False))}::jsonb)")
    for key in timing_specs:
        sheet, _, case = key.partition("::")
        if (sheet, case) not in {(s.lower(), cn) for (s, cn) in rule_by_case}:
            die(f"timing override {key!r} matches no workbook case")
    w("INSERT INTO translation_keys (id, key)")
    w("VALUES")
    w(",\n".join(keys) + ";")
    w("")
    w("INSERT INTO translations (text_id, locale_id, text)")
    w("VALUES")
    w(",\n".join(texts) + ";")
    w("")
    w("INSERT INTO interaction_rules (id, public_id, title_text_id, interaction_type, rule_scope, base_risk_level_id, medical_review_status, publication_status, version, topic_id, is_risk_inherited_from_topic, scope_note_text_id, conditions_text_id, clinical_conclusion_text_id, significance_text_id, numeric_effect_text_id, source_workbook_sheet, source_workbook_case_name)")
    w("VALUES")
    w(",\n".join(rule_rows) + ";")
    w("")
    w("INSERT INTO interaction_rule_participants (id, interaction_rule_id, concept_id, participant_role, match_scope, required_for_match, alternative_group)")
    w("VALUES")
    w(",\n".join(participant_rows) + ";")
    w("")

    # ---- evidence links and findings -------------------------------------
    link_rows, finding_rows = [], []
    used_effects = set()
    for t in topics:
        for e in t["evidence"]:
            s = e["source_info"]
            targets = [a.strip() for a in (e["applies"] or "").split("\n") if a.strip()]
            if not targets:
                die(f"evidence row {t['sheet']}:{e['row']} has an empty 'Applies to'")
            effect = effect_specs.get(f"{t['sheet']}::{e['row']}")
            if effect:
                if not e["source"].startswith(effect["source"][:40]):
                    die(f"evidence_effects {t['sheet']}::{e['row']} names source {effect['source'][:40]!r} but the row cites {e['source'][:40]!r}")
                used_effects.add(f"{t['sheet']}::{e['row']}")
            for name in targets:
                rule = rule_by_case.get((t["sheet"], name.lower()))
                if rule is None:
                    die(f"evidence row {t['sheet']}:{e['row']} applies to unknown case {name!r}")
                if s["public_id"] not in rule["links"]:
                    rule["links"][s["public_id"]] = {"order": len(rule["links"]) + 1, "findings": 0}
                    link_rows.append(f"  ({rule['id']}, {s['id']}, {rule['links'][s['public_id']]['order']}, {q(s['evidence_role'])})")
                link = rule["links"][s["public_id"]]
                if not e["finding"]:
                    sys.stderr.write(f"note: evidence row {t['sheet']}:{e['row']} has no finding text; linked without a finding\n")
                    continue
                link["findings"] += 1
                eff = effect or {}
                finding_rows.append(
                    f"  ({rule['id']}, {s['id']}, {link['findings']}, {q(e['finding'])}, {q(e['limitations'])}, {q(e['locator'])}, "
                    f"{q(e['guidance'])}, {q(eff.get('study_design') or s['study_design'])}, {q(eff.get('population'))}, "
                    f"{q(eff.get('sample_size'))}, {q(eff.get('effect_metric'))}, {q(eff.get('effect_value'))}, "
                    f"{q(eff.get('effect_ci_low'))}, {q(eff.get('effect_ci_high'))}, {q(eff.get('p_value'))}, {q(eff.get('effect_note'))}, 'draft')")
    missing = set(effect_specs) - used_effects
    if missing:
        die(f"evidence_effects entries match no evidence row: {sorted(missing)}")
    w("-- ---------------------------------------------------------------------------")
    w("-- Evidence: one link per rule x source, one finding per workbook Evidence row")
    w("-- x case it applies to. Effect numbers only where the overrides file states")
    w("-- them for a row that gives them plainly.")
    w("-- ---------------------------------------------------------------------------")
    w("INSERT INTO interaction_rule_sources (interaction_rule_id, evidence_source_id, source_order, evidence_role)")
    w("VALUES")
    w(",\n".join(link_rows) + ";")
    w("")
    w("INSERT INTO evidence_findings (interaction_rule_id, evidence_source_id, finding_order, finding_text, limitations_text, source_locator, source_guidance_text, study_design, population, sample_size, effect_metric, effect_value, effect_ci_low, effect_ci_high, p_value, effect_note, status)")
    w("VALUES")
    w(",\n".join(finding_rows) + ";")
    w("")
    w("-- ---------------------------------------------------------------------------")
    w("-- Timing: the Tühja kõhuga / Päevaaeg instructions; typed columns from the")
    w("-- overrides file, NULL where the text gives no clear window.")
    w("-- ---------------------------------------------------------------------------")
    w("INSERT INTO timing_recommendations (id, interaction_rule_id, timing_type, instruction_text_id, status, anchor, relation, min_minutes, max_minutes, alternative_group, time_of_day, stay_upright_minutes, with_water_ml_min, with_water_ml_max, requirement_strength)")
    w("VALUES")
    w(",\n".join(timing_rows) + ";")
    w("")
    w("INSERT INTO content_audit_log (entity_type, entity_id, action, new_value_json)")
    w("VALUES")
    w(",\n".join(audit_rows) + ";")
    w("")
    for table in ("translation_keys", "health_concepts", "concept_aliases", "concept_relationships", "evidence_sources",
                  "interaction_topics", "interaction_rules", "interaction_rule_participants", "evidence_findings",
                  "timing_recommendations", "content_audit_log"):
        w(f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), (SELECT max(id) FROM {table}));")
    w("")
    w("COMMIT;")
    w("")
    OUT_SQL.write_text("\n".join(out), encoding="utf-8")

    # ---- map --------------------------------------------------------------
    with OUT_MAP.open("w", encoding="utf-8", newline="") as fh:
        wr = csv.writer(fh)
        wr.writerow(["factor_name", "sheets", "resolution", "public_ids", "concept_type", "concept_category", "how",
                     "alias_action", "relationships", "member_of", "note"])
        for row in catalog.map_rows.values():
            pids = row["public_ids"]
            types = ";".join(catalog.concepts[p]["type"] for p in pids)
            cats = ";".join(catalog.concepts[p]["category"] or "" for p in pids)
            alias_actions = []
            for p in pids:
                for m in catalog.alias_moves:
                    if m["to"] == p and m["alias"].lower() == row["factor_name"].lower():
                        alias_actions.append(f"alias {m['alias']!r} moved from {m['from']}")
                for a in catalog.new_aliases:
                    if a["concept"] == p and a["alias"].lower() == row["factor_name"].lower():
                        alias_actions.append(f"alias added to {p}")
            rels = [f"{f} {rt} {t}" for (f, t, rt, _) in catalog.new_relationships if f in pids]
            wr.writerow([row["factor_name"], "; ".join(row["sheets"]), row["resolution"], ";".join(pids), types, cats,
                         row["how"], "; ".join(alias_actions), "; ".join(rels), row["member_of"], row["note"]])
        wr.writerow([])
        wr.writerow(["# retyped seed concepts"])
        for r in catalog.retypes:
            wr.writerow([r["name"], "", "retype", r["public_id"], r["type"], r["category"], "override",
                         "", "", "", f"was {r['from_type']}/{r['from_category']}: {r['note'] or ''}"])
        wr.writerow(["# rejected seed aliases"])
        for r in catalog.alias_rejects:
            wr.writerow([r["alias"], "", "reject_alias", r["concept"], "", "", "override", f"alias id {r['alias_id']} rejected", "", "", r["note"] or ""])

    # ---- summary ----------------------------------------------------------
    n_links = len(link_rows)
    sys.stderr.write(
        f"topics={len(topics)} cases={len(resolved_cases)} evidence_rows={sum(len(t['evidence']) for t in topics)} "
        f"sources={len(sources)} doi={sum(1 for s in sources.values() if s['doi'])} pmid={sum(1 for s in sources.values() if s['pmid'])} "
        f"pmcid={sum(1 for s in sources.values() if s['pmcid'])} rule_sources={n_links} findings={len(finding_rows)} "
        f"participants={n_participants} timing_rows={n_timing} new_concepts={len(catalog.new_concepts)} "
        f"new_aliases={len(catalog.new_aliases)} moved_aliases={len(catalog.alias_moves)} rejected_aliases={len(catalog.alias_rejects)} "
        f"relationships={len(catalog.new_relationships)} retyped={len(catalog.retypes)}\n")
    sys.stderr.write(f"wrote {OUT_SQL.relative_to(REPO)} and {OUT_MAP.relative_to(REPO)}\n")


if __name__ == "__main__":
    main(sys.argv)
