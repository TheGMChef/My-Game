#!/usr/bin/env python3
"""Stage 1: faithful parse of datasheet PDFs into raw JSON.

Reads layout-preserved text (pdftotext -layout) and records what is printed,
with no rule interpretation. Anything it cannot place goes into `unparsed`
so nothing is silently dropped. Output stays local (data/local/), never in git.

Usage: parse_datasheets.py <input_dir> <output_dir>
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Poppler keeps weapon rows together with -layout. xpdf, which Git for Windows ships, needs -table.
LAYOUT_FLAG = os.environ.get("PDFTOTEXT_LAYOUT", "-table" if os.name == "nt" else "-layout")
NUM = r"(?:\d+|D\d+(?:\+\d+)?|\d+D\d+(?:\+\d+)?|N/A|-)"
STAT_ROW = re.compile(
    r"^\s*(?P<m>\d+\+?\"|-)\s+(?P<t>\d+)\s+(?P<sv>\d\+|-)\s+(?P<w>\d+)\s+(?P<ld>\d\+|-)\s+(?P<oc>\d+)(?:\s{2,}(?P<label>\S.*?))?\s*$")
WEAPON_STATS = re.compile(
    r"(?P<range>\d+\"|Melee)\s+(?P<a>" + NUM + r")\s+(?P<skill>\d\+|N/A)\s+(?P<s>" + NUM + r"|\d+\+?)\s+(?P<ap>-?\d+)\s+(?P<d>" + NUM + r")\s*$")


def pdf_pages(pdf: Path, flag: str) -> list[str]:
    out = subprocess.run(["pdftotext", flag, "-enc", "UTF-8", str(pdf), "-"], capture_output=True, check=True).stdout
    return out.decode("utf-8").split("")


def text_of(pdf: Path) -> list[str]:
    """The weapon table page from LAYOUT_FLAG, the rest from -layout, which keeps spaces in names."""
    pages = pdf_pages(pdf, "-layout")
    if LAYOUT_FLAG != "-layout":
        pages[0] = pdf_pages(pdf, LAYOUT_FLAG)[0]
    return pages


def parse_page1(lines: list[str], rec: dict) -> None:
    rec["name"] = next((l.strip() for l in lines if l.strip()), "")
    # stat rows
    hdr = next((i for i, l in enumerate(lines) if re.search(r"\bM\s+T\s+SV\s+W\s+LD\s+OC\b", l)), None)
    rec["profiles"] = []
    if hdr is not None:
        for l in lines[hdr + 1: hdr + 14]:
            m = STAT_ROW.match(l)
            if m:
                rec["profiles"].append({k: v for k, v in m.groupdict().items() if v is not None})
            if re.search(r"RANGED WEAPONS|MELEE WEAPONS", l):
                break
    # weapons table
    wh = next((i for i, l in enumerate(lines) if "RANGED WEAPONS" in l or "MELEE WEAPONS" in l), None)
    rec["weapons"] = []
    rec["ability_text"] = []
    if wh is None:
        rec["unparsed"].append("no RANGED WEAPONS header")
        return
    cut = lines[wh].find("ABILITIES")
    end = next((i for i, l in enumerate(lines) if i > wh and l.lstrip().startswith("KEYWORDS")), len(lines))
    left_lines, right_lines = [], []
    for l in lines[wh + 1: end]:
        left_lines.append(l[:cut].rstrip() if cut > 0 else l.rstrip())
        right_lines.append(l[cut:].strip() if cut > 0 and len(l) > cut else "")
    rec["ability_text"] = [r for r in right_lines if r]
    kind = "melee" if "MELEE WEAPONS" in lines[wh] else "ranged"
    rec["weapon_notes"] = []
    pending: list[str] = []
    last = None
    for l in left_lines:
        s = l.strip()
        if not s:
            continue
        if s.startswith("MELEE WEAPONS"):
            kind, pending, last = "melee", [], None
            continue
        m = WEAPON_STATS.search(s)
        if m:
            prefix = s[: m.start()].strip()
            name = " ".join(pending + ([prefix] if prefix else [])).strip()
            pending = []
            last = {"name": name, "kind": kind, **{k: m.group(k) for k in ("range", "a", "skill", "s", "ap", "d")}}
            rec["weapons"].append(last)
        elif s.startswith("[") and last is not None and "tags_raw" not in last:
            last["tags_raw"] = s
        elif s.startswith("[") and last is not None:
            last["tags_raw"] += " " + s
        elif s.startswith("Before selecting targets") or re.match(r"^[A-Z][\w' ]+:\s+\S", s) and not pending:
            rec["weapon_notes"].append(s)
        else:
            if last is not None and last.get("tags_raw", "").count("[") > last.get("tags_raw", "").count("]"):
                last["tags_raw"] += " " + s
            else:
                pending.append(s)
    if pending:
        rec["unparsed"].append("dangling weapon text: " + " ".join(pending))


def parse_keywords(lines: list[str], rec: dict) -> None:
    """KEYWORDS and FACTION KEYWORDS, from the page's last lines."""
    start = next((i for i, l in enumerate(lines) if l.lstrip().startswith("KEYWORDS")), None)
    if start is None:
        return
    kw_block = lines[start:]
    fk_col = None
    for l in kw_block:
        if "FACTION KEYWORDS" in l:
            fk_col = l.find("FACTION KEYWORDS")
            break
    kw_left, fk_right = [], []
    for l in kw_block:
        if not l.strip():
            continue
        left = l[:fk_col] if fk_col else l
        right = l[fk_col:] if fk_col and len(l) > fk_col else ""
        if left.strip():
            kw_left.append(left.strip())
        if right.strip():
            fk_right.append(right.strip())
    kws = re.sub(r"^KEYWORDS:\s*", "", " ".join(kw_left))
    kws = re.sub(r"[\x00-\x1f]", "", kws)
    rec["keywords"] = [" ".join(k.split()) for k in re.split(r",\s*", kws) if k.strip()]
    fk = re.sub(r"^FACTION KEYWORDS:\s*", "", " ".join(fk_right))
    rec["faction_keywords"] = [" ".join(k.split()) for k in re.split(r",\s*", fk) if k.strip()]


def parse_page2(lines: list[str], rec: dict) -> None:
    rec["page2_raw"] = [l.rstrip() for l in lines if l.strip()]
    joined = "\n".join(lines)
    m = re.search(r"UNIT COMPOSITION(.*?)(?:LEADER|SUPREME|TRANSPORT|KEYWORDS|\Z)", joined, re.S)
    comp = []
    if m:
        # take the right-hand column of lines after the header
        hdr_line = next(l for l in lines if "UNIT COMPOSITION" in l)
        col = hdr_line.find("UNIT COMPOSITION")
        for l in lines[lines.index(hdr_line) + 1:]:
            if re.search(r"^\s*(KEYWORDS|LEADER|TRANSPORT|SUPREME)", l[col:] if len(l) > col else ""):
                break
            if len(l) > col and l[col:].strip():
                comp.append(l[col:].strip())
            if re.match(r"^\s*KEYWORDS", l):
                break
    rec["composition_raw"] = comp


def parse_pdf(pdf: Path) -> dict:
    pages = text_of(pdf)
    rec = {"source_file": pdf.name, "unparsed": []}
    p1 = pages[0].splitlines()
    parse_page1(p1, rec)
    # -table can split words in large text, so names and keywords come from -layout.
    plain = pdf_pages(pdf, "-layout")[0].splitlines()
    rec["name"] = next((l.strip() for l in plain if l.strip()), rec["name"])
    parse_keywords(plain, rec)
    full = "\n".join(pages)
    inv = re.search(r"INVULNERABLE SAVE\s*(\d)\+", full) or re.search(r"(\d)\+\s+INVULNERABLE SAVE", full)
    rec["invuln_printed"] = int(inv.group(1)) if inv else None
    if len(pages) > 1 and pages[1].strip():
        parse_page2(pages[1].splitlines(), rec)
    rec["raw_pages"] = [p for p in pages if p.strip()]
    return rec


def main() -> int:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    n = bad = 0
    for pdf in sorted(src.rglob("*.pdf")):
        if pdf.name.lower() in ("index.pdf", "adse.pdf"):
            continue
        n += 1
        try:
            rec = parse_pdf(pdf)
        except Exception as e:  # keep going, report
            rec = {"source_file": pdf.name, "unparsed": [f"EXCEPTION {e!r}"]}
        rec["folder"] = str(pdf.parent.relative_to(src))
        (dst / (pdf.stem.replace("/", "_") + ".json")).write_text(json.dumps(rec, indent=1, ensure_ascii=False), encoding="utf-8")
        if rec["unparsed"] or not rec.get("profiles") or not rec.get("weapons"):
            bad += 1
    print(f"{n} parsed, {bad} flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
