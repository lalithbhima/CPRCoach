#!/usr/bin/env python3
"""Merge guided_step_* and learn_* translations into locale JSON files."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "VisionCPRCoach" / "Resources" / "Localizations"
TRANS_DIR = Path(__file__).resolve().parent / "translations"
SKIP = {"en", "te", "hi", "es", "fr", "de"}


def ordered_merge(en: dict, existing: dict, new_keys: dict) -> dict:
    """Preserve en.json key order; fill missing guided/learn keys only."""
    out = dict(existing)
    for key in en:
        if key.startswith("guided_step_") or key.startswith("learn_"):
            if key not in out and key in new_keys:
                out[key] = new_keys[key]
    # Reorder to match en.json
    ordered = {}
    for key in en:
        if key in out:
            ordered[key] = out[key]
    for key in out:
        if key not in ordered:
            ordered[key] = out[key]
    return ordered


def main() -> int:
    with open(LOC / "en.json", encoding="utf-8") as f:
        en = json.load(f)

    updated = []
    skipped = []
    missing_files = []

    for path in sorted(TRANS_DIR.glob("*.json")):
        code = path.stem
        if code in SKIP:
            skipped.append(code)
            continue
        locale_path = LOC / f"{code}.json"
        if not locale_path.exists():
            missing_files.append(code)
            continue
        with open(path, encoding="utf-8") as f:
            translations = json.load(f)
        with open(locale_path, encoding="utf-8") as f:
            existing = json.load(f)
        merged = ordered_merge(en, existing, translations)
        with open(locale_path, "w", encoding="utf-8") as f:
            json.dump(merged, f, ensure_ascii=False, indent=2)
            f.write("\n")
        updated.append(code)

    print("Updated:", ", ".join(updated) if updated else "(none)")
    if skipped:
        print("Skipped:", ", ".join(skipped))
    if missing_files:
        print("Missing locale files:", ", ".join(missing_files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
