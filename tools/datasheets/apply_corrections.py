#!/usr/bin/env python3
"""Applies local correction files to a built army, so rebuilds keep 11th edition changes.

A correction file holds "units" (changes keyed by unit name) and "new_units". It stays local
(data/local/corrections/), never in git. Every change is listed in the returned log, and a
name that matches nothing is reported, not skipped silently.

Usage: apply_corrections.py <army.json> <corrections.json> <report.md>
"""
import json
import sys
from pathlib import Path

LIST_CHANGES = {"keywords": ("add_keywords", "remove_keywords"), "abilities": ("add_abilities", "remove_abilities")}


def change_list(item, field, add, remove):
    current = list(item.get(field, []))
    current += [x for x in add if x not in current]
    item[field] = [x for x in current if x not in remove]


def fix_weapon(weapon, change):
    weapon.update(change.get("set", {}))
    change_list(weapon, "abilities", change.get("add_abilities", []), change.get("remove_abilities", []))


def fix_unit(unit, change, problems):
    unit.update(change.get("set", {}))
    for field, (add, remove) in LIST_CHANGES.items():
        change_list(unit, field, change.get(add, []), change.get(remove, []))
    change_list(unit, "faction_abilities", change.get("add_faction_abilities", []), [])
    if "replace_weapons" in change:
        unit["weapons"] = list(change["replace_weapons"])
    for bucket in ("weapons", "all_weapons"):
        names = change.get("remove_weapons", [])
        unit[bucket] = [w for w in unit.get(bucket, []) if w["name"] not in names]
    unit["weapons"] += change.get("add_weapons", [])
    for name, weapon_change in change.get("weapons", {}).items():
        hits = [w for bucket in ("weapons", "all_weapons") for w in unit.get(bucket, []) if w["name"] == name]
        if not hits:
            problems.append(f"{unit['name']}: no weapon named {name}")
        for w in hits:
            fix_weapon(w, weapon_change)


def apply(army, corrections):
    """Change the army in place. Returns (log lines, problems)."""
    units = {u["name"]: u for u in army["units"]}
    log, problems = [], []
    for name, change in corrections.get("units", {}).items():
        if name not in units:
            problems.append(f"no unit named {name}")
            continue
        fix_unit(units[name], change, problems)
        units[name]["corrected_from"] = change.get("source", "")
        note = " (uncertain)" if change.get("uncertain") else ""
        log.append(f"- {name}: corrected from {change.get('source', 'unknown source')}{note}")
    for unit in corrections.get("new_units", []):
        if unit["name"] in units:
            problems.append(f"new unit already exists: {unit['name']}")
            continue
        army["units"].append(unit)
        log.append(f"- {unit['name']}: added from {unit.get('source', 'unknown source')}")
    return log, problems


def main() -> int:
    army_path, corrections_path, report_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    data = json.loads(army_path.read_text(encoding="utf-8"))
    corrections = json.loads(corrections_path.read_text(encoding="utf-8"))
    log, problems = apply(data["armies"][0], corrections)
    army_path.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    lines = ["", "## Corrections applied", ""] + log + ["", "## Corrections that did not apply", ""] + [f"- {p}" for p in problems]
    with report_path.open("a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(log)} corrections applied, {len(problems)} problems")
    for p in problems:
        print(f"  PROBLEM: {p}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
