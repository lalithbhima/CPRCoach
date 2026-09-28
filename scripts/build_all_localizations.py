#!/usr/bin/env python3
"""Validate locale files: every language in languages.json must have all keys from en.json."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "VisionCPRCoach" / "Resources"
LOC = RES / "Localizations"
LANGS = RES / "languages.json"


def main() -> int:
    with open(RES / "Localizations" / "en.json", encoding="utf-8") as f:
        en = json.load(f)
    with open(LANGS, encoding="utf-8") as f:
        languages = json.load(f)

    en_keys = set(en.keys())
    errors = []

    for lang in languages:
        code = lang["code"]
        path = LOC / f"{code}.json"
        if not path.exists():
            errors.append(f"MISSING FILE: {code}.json")
            continue
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        missing = en_keys - set(data.keys())
        extra = set(data.keys()) - en_keys
        if missing:
            errors.append(f"{code}: missing {len(missing)} keys (e.g. {list(missing)[:3]})")
        if extra:
            errors.append(f"{code}: {len(extra)} extra keys")
        english_left = sum(1 for k in en_keys if data.get(k) == en.get(k) and code != "en")
        if english_left > 15 and code != "en":
            errors.append(f"{code}: {english_left} keys still identical to English")

    if errors:
        print("Locale validation issues:")
        for e in errors:
            print(" -", e)
        return 1
    print(f"OK: {len(languages)} languages, {len(en_keys)} keys each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
