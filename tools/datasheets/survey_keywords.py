#!/usr/bin/env python3
"""Counts every weapon ability, core ability and unit keyword in parsed raw datasheets.

Usage: survey_keywords.py <raw_dir> [<raw_dir> ...]
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

from map_datasheets import clean_tag, split_tags


def main() -> None:
    tags, core, faction, unit = Counter(), Counter(), Counter(), Counter()
    for folder in sys.argv[1:]:
        for f in Path(folder).glob("*.json"):
            rec = json.loads(f.read_text(encoding="utf-8"))
            for w in rec.get("weapons", []):
                found = re.findall(r"\[(.*?)\]", w.get("name", "")) + [w.get("tags_raw", "")]
                for text in found:
                    for t in split_tags(text):
                        tags[re.sub(r"\s*(\d+\+?|D\d+)$", "", clean_tag(t))] += 1
            for line in rec.get("ability_text", []):
                for label, bucket in (("CORE:", core), ("FACTION:", faction)):
                    if line.startswith(label):
                        for part in line[len(label):].split(","):
                            bucket[re.sub(r"\s+\d.*$|\s+D\d.*$", "", part.strip())] += 1
            unit.update(k.upper() for k in rec.get("keywords", []))
    for title, counts in (("WEAPON", tags), ("CORE", core), ("FACTION", faction)):
        print(f"--- {title}")
        for k, v in counts.most_common():
            print(f"{v:5}  {k}")
    print("--- UNIT (top 40)")
    for k, v in unit.most_common(40):
        print(f"{v:5}  {k}")


if __name__ == "__main__":
    main()
