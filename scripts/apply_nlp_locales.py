#!/usr/bin/env python3
"""Apply localized nlp_* keys to target locale JSON files."""
import json
import sys
from pathlib import Path

from nlp_locale_data import NLP_LOCALES

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "VisionCPRCoach" / "Resources" / "Localizations"

SKIP = {"en", "fil", "te", "hi", "es"}


def main() -> int:
    updated: list[str] = []
    missing_locales: list[str] = []

    for code, tokens in sorted(NLP_LOCALES.items()):
        path = LOC / f"{code}.json"
        if not path.exists():
            missing_locales.append(code)
            continue
        data = json.load(open(path, encoding="utf-8"))
        data.update(tokens)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        updated.append(f"{code}.json")

    if missing_locales:
        print("Missing files:", ", ".join(missing_locales), file=sys.stderr)
        return 1

    print(f"Updated {len(updated)} files:")
    for name in updated:
        print(f"  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
