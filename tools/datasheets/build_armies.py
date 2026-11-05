#!/usr/bin/env python3
"""Builds every army file from a folder of faction folders of datasheet PDFs.

Each faction becomes data/local/army_<faction>.json plus a conversion report beside it.
Output stays local (data/local/), never in git.

Usage: build_armies.py <pdf_root>
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE.parent.parent / "data" / "local"
NAMES = {"tau": "T'au Empire", "votann": "Leagues of Votann"}


def main() -> int:
    root = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for faction in sorted(p for p in root.iterdir() if p.is_dir()):
        with tempfile.TemporaryDirectory() as raw:
            for step in (
                ["parse_datasheets.py", str(faction), raw],
                ["map_datasheets.py", raw, str(OUT / f"army_{faction.name}.json"),
                 str(OUT / f"report_{faction.name}.md"), NAMES.get(faction.name, faction.name.replace("_", " ").title())],
            ):
                result = subprocess.run([sys.executable, str(HERE / step[0]), *step[1:]], capture_output=True, text=True)
                print(f"{faction.name}: {result.stdout.strip().splitlines()[-1] if result.stdout.strip() else result.stderr[-300:]}")
                if result.returncode != 0:
                    failures += 1
                    break
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
