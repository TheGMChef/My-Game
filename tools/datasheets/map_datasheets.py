#!/usr/bin/env python3
"""Stage 2: map raw parsed datasheets to the engine's unit format.

Every judgement call is logged as an issue on the unit (severity: info, warn,
error). Nothing is dropped silently. Output stays local (data/local/).

Usage: map_datasheets.py <raw_dir> <armies_out.json> <report_out.md> <army name>
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Weapon abilities the engine resolves today (src/engine/attack_resolver.gd).
ENGINE_SUPPORTED = {
    "RAPID FIRE", "MELTA", "BLAST", "TORRENT", "LETHAL HITS", "SUSTAINED HITS", "DEVASTATING WOUNDS",
    "HEAVY", "CLOSE-QUARTERS", "IGNORES COVER", "ANTI", "HAZARDOUS", "EXTRA ATTACKS", "LANCE",
}
TYPO_FIXES = {"ANTI-VECHILE": "ANTI-VEHICLE", "DEVESTATING WOUNDS": "DEVASTATING WOUNDS", "TWIN -LINKED": "TWIN-LINKED"}


def num(s, default=0):
    m = re.search(r"-?\d+", s or "")
    return int(m.group()) if m else default


def clean_tag(t: str) -> str:
    t = re.sub(r"[\x00-\x1f*]", "", t).strip().upper()
    for bad, good in TYPO_FIXES.items():
        t = t.replace(bad, good)
    return t


def split_tags(text: str):
    if not text:
        return []
    return [t for t in (x.strip() for x in re.split(r"\]\s*\[|,", text.strip("[] "))) if t]


def weapon_of(w, unit_issues, uname):
    name, tags = w["name"], []
    m = re.search(r"\s*\[(.*?)\]\s*$", name)
    if m:
        name, tags = name[: m.start()].strip(), split_tags(m.group(1))
    if w.get("tags_raw"):
        tags += split_tags(w["tags_raw"])
    abilities = []
    for t in tags:
        c = clean_tag(t)
        if c != t.upper().strip():
            unit_issues.append(("warn", f"typo or stray character in weapon tag '{t}' on {name}; read as '{c}'"))
        abilities.append(c)
    skill = 0 if w["skill"] == "N/A" else num(w["skill"])
    if w["skill"] == "N/A" and "TORRENT" not in abilities:
        unit_issues.append(("warn", f"{name}: skill N/A without TORRENT"))
    d = {"name": name, "range": 0 if w["range"] == "Melee" else num(w["range"]),
         "attacks": w["a"], "skill": skill, "strength": w["s"], "ap": abs(num(w["ap"])), "damage": w["d"],
         "abilities": abilities}
    if d["strength"].isdigit():
        d["strength"] = int(d["strength"])
    for a in abilities:
        base = re.sub(r"\s*(\d+\+?|D\d+)$", "", a)
        base = "ANTI" if base.startswith("ANTI-") else base.replace("PISTOL", "CLOSE-QUARTERS")
        if base not in ENGINE_SUPPORTED:
            unit_issues.append(("info", f"{name}: [{a}] not applied by the engine yet"))
    return d


def norm(s):
    s = s.lower().replace("’", "'")
    return re.sub(r"[^a-z0-9' ]", "", s).strip()


def singular(s):
    for suf, rep in (("ies", "y"), ("es", ""), ("s", "")):
        if s.endswith(suf) and len(s) > 3:
            yield s[: -len(suf)] + rep
    yield s


def match_weapon(item, weapons):
    n = norm(item)
    cands = {n, *singular(n)}
    hits = [w for w in weapons if norm(w["name"]) in cands or any(norm(w["name"]).startswith(c + " ") for c in cands)]
    return hits


def composition(rec, issues):
    comp = rec.get("composition_raw", [])
    bullets, equip_lines, in_equip = [], [], False
    for l in comp:
        if l.startswith("■"):
            bullets.append(l[1:].strip()); in_equip = False
        elif "FACTION KEYWORDS" in l:
            continue
        elif re.search(r"equipped with", l):
            in_equip = True; equip_lines.append(l)
        elif in_equip or (equip_lines and not l.startswith("■")):
            equip_lines.append(l)
    lo = hi = 0
    for b in bullets:
        m = re.match(r"(\d+)(?:\s*-\s*(\d+))?\s+", b)
        if m:
            lo += int(m.group(1)); hi += int(m.group(2) or m.group(1))
        else:
            issues.append(("warn", f"composition line not understood: {b}"))
    if not bullets:
        issues.append(("error", "no unit composition found"))
    equip = " ".join(equip_lines)
    equip = re.sub(r"^.*?equipped with:\s*", "", equip)
    items = [i.strip(" .") for i in equip.split(";") if i.strip(" .")]
    return bullets, max(lo, 1), max(hi, 1), items


def map_unit(rec):
    issues = []
    prof = rec["profiles"][0] if rec.get("profiles") else None
    if not prof:
        return None, [("error", "no stat line")]
    if len(rec["profiles"]) > 1:
        names = ", ".join(p.get("label", "?") for p in rec["profiles"])
        issues.append(("warn", f"{len(rec['profiles'])} model profiles ({names}); engine takes the first for the whole unit"))
    weapons = [weapon_of(w, issues, rec["name"]) for w in rec.get("weapons", [])]
    bullets, lo, hi, items = composition(rec, issues)
    chosen, wargear_items, seen = [], [], set()
    for it in items:
        q = re.match(r"(\d+)\s+(.*)", it)
        base = q.group(2) if q else it
        hits = match_weapon(base, weapons)
        if hits:
            for h in hits:
                if h["name"] not in seen:
                    seen.add(h["name"])
                    chosen.append({**h, "count": int(q.group(1)) if q else 1})
        else:
            wargear_items.append(it)
    if not chosen:
        chosen = weapons
        issues.append(("warn", "default loadout not matched to the weapon table; every weapon included"))
    groups = defaultdict(list)
    for w in chosen:
        groups[w["name"].split(" – ")[0].split(" - ")[0]].append(w)
    final = []
    for g, ws in groups.items():
        final.append(ws[0])
        if len(ws) > 1:
            issues.append(("warn", f"{g}: {len(ws)} profiles to choose from; only '{ws[0]['name']}' kept (engine has no profile choice yet)"))
    unmatched_weapons = [w["name"] for w in weapons if w not in chosen]
    if unmatched_weapons:
        issues.append(("info", f"optional weapons not in default loadout: {', '.join(unmatched_weapons)}"))
    if wargear_items:
        issues.append(("info", f"default wargear not modelled: {'; '.join(wargear_items)}"))
    if rec.get("page2_raw") and any(re.search(r"WARGEAR OPTIONS", x) for x in rec["page2_raw"]):
        issues.append(("info", "has wargear options (not selectable yet)"))
    if any(re.search(r"\bLEADER\b", x) for x in rec.get("page2_raw", [])) or "Leader" in " ".join(rec.get("ability_text", [])):
        issues.append(("info", "Leader: attachment not modelled yet"))
    kws = [k.upper() for k in rec.get("keywords", [])]
    unit = {
        "name": rec["name"], "models": lo, "models_min": lo, "models_max": hi,
        "move": num(prof["m"]), "toughness": int(prof["t"]), "save": num(prof["sv"], 7),
        "invuln": rec.get("invuln_printed") or 0, "wounds": int(prof["w"]),
        "leadership": num(prof["ld"], 6), "oc": int(prof["oc"]),
        "base_mm": 0, "keywords": kws, "faction_keywords": [k.upper() for k in rec.get("faction_keywords", [])],
        "weapons": final, "all_weapons": weapons,
        "ability_text": rec.get("ability_text", []), "source": rec["source_file"],
    }
    if "+" in prof["m"]:
        issues.append(("warn", f"aircraft-style move {prof['m']}"))
    unit["base_mm"] = 0
    issues.append(("info", "base size not on datasheet; engine default used"))
    # sanity ranges
    for k, lim in (("toughness", (1, 16)), ("wounds", (1, 100)), ("move", (0, 20)), ("save", (2, 7))):
        v = unit[k]
        if not (lim[0] <= v <= lim[1]):
            issues.append(("error", f"{k}={v} out of range {lim}"))
    if not final:
        issues.append(("info", "no weapons"))
    return unit, issues


def main():
    raw, out, report, army = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
    units, all_issues = [], {}
    sev = Counter()
    for f in sorted(raw.glob("*.json")):
        rec = json.load(open(f))
        for u in rec.get("unparsed", []):
            all_issues.setdefault(rec["source_file"], []).append(("error", f"parse: {u}"))
        unit, iss = map_unit(rec) if rec.get("profiles") else (None, [("error", "no stat line")])
        if unit:
            units.append(unit)
        for s, m in iss:
            sev[s] += 1
        if iss:
            all_issues.setdefault(rec["source_file"], []).extend(iss)
    out.write_text(json.dumps({"note": "Local conversion of user-supplied datasheets. Not for the repo.",
                               "armies": [{"name": army, "units": units}]}, indent=1, ensure_ascii=False))
    lines = [f"# {army}: conversion report", "", f"{len(units)} units mapped. Issues: {dict(sev)}", ""]
    unsupported = Counter(m for iss in all_issues.values() for s, m in iss if "not applied" in m)
    kw = Counter(re.search(r"\[(.*?)\]", m).group(1) for m in unsupported.elements())
    lines += ["## Weapon abilities the engine cannot apply (count of weapons)", ""]
    lines += [f"- {k}: {v}" for k, v in sorted(kw.items(), key=lambda x: -x[1])] + [""]
    lines += ["## Errors and warnings by unit", ""]
    for src, iss in sorted(all_issues.items()):
        bad = [(s, m) for s, m in iss if s in ("error", "warn")]
        if bad:
            lines.append(f"### {src}")
            lines += [f"- {s}: {m}" for s, m in bad]
    report.write_text("\n".join(lines))
    print(f"{army}: {len(units)} units; {dict(sev)}")


if __name__ == "__main__":
    main()
