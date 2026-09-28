#!/usr/bin/env python3
"""Flatten learn_en.json into locale keys and merge into en.json."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEARN = ROOT / "VisionCPRCoach" / "Resources" / "Learn" / "learn_en.json"
EN = ROOT / "VisionCPRCoach" / "Resources" / "Localizations" / "en.json"

MODULE_ORDER = ["assess", "compress", "quality", "aed"]


def flatten(modules: list) -> dict[str, str]:
    out: dict[str, str] = {}
    by_id = {m["id"]: m for m in modules}
    for mid in MODULE_ORDER:
        m = by_id[mid]
        prefix = f"learn_{mid}"
        out[f"{prefix}_title"] = m["title"]
        out[f"{prefix}_summary"] = m["summary"]
        out[f"{prefix}_overview"] = m["overview"]
        for i, bullet in enumerate(m["bullets"]):
            out[f"{prefix}_bullet_{i}"] = bullet
        for i, step in enumerate(m["steps"]):
            out[f"{prefix}_step_{i}"] = step
    return out


def main() -> None:
    with open(LEARN, encoding="utf-8") as f:
        learn = json.load(f)
    with open(EN, encoding="utf-8") as f:
        en = json.load(f)
    en.update(flatten(learn["modules"]))
    EN.write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added {len(flatten(learn['modules']))} learn keys to en.json ({len(en)} total)")


if __name__ == "__main__":
    main()
