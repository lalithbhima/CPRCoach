#!/usr/bin/env python3
"""Translate missing locale keys from en.json into each language file."""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "VisionCPRCoach" / "Resources" / "Localizations"
LANGS = ROOT / "VisionCPRCoach" / "Resources" / "languages.json"
SECRET = ROOT / "Config" / "secret.ts"
MODEL = "openrouter/free"
BATCH_SIZE = 40
SLEEP_BETWEEN_LANGS = 12


def load_api_key() -> str:
    text = SECRET.read_text(encoding="utf-8")
    m = re.search(r'OPENROUTER_API_KEY\s*=\s*"([^"]+)"', text)
    if not m:
        raise SystemExit("OPENROUTER_API_KEY not found")
    return m.group(1).strip()


def openrouter_translate(api_key: str, lang: dict, subset: dict) -> dict:
    system = (
        "You translate strings for a CPR training mobile app. "
        "Return a JSON object with exactly the same keys and translated values. "
        "Preserve %@ placeholders, numbers, and medical accuracy. JSON only."
    )
    user = (
        f"Target language: {lang['native']} ({lang['name']}), locale {lang['speech']}.\n"
        f"Translate:\n{json.dumps(subset, ensure_ascii=False)}"
    )
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://vision-cpr-coach.local",
            "X-Title": "VisionCPRCoach i18n",
        },
        method="POST",
    )
    delay = 5
    for attempt in range(8):
        try:
            with urllib.request.urlopen(req, timeout=240) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            content = body["choices"][0]["message"]["content"]
            return json.loads(content)
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 503) and attempt < 7:
                time.sleep(delay)
                delay = min(delay * 2, 90)
                continue
            raise
    raise RuntimeError("translate failed")


def main() -> int:
    api_key = load_api_key()
    with open(LOC / "en.json", encoding="utf-8") as f:
        en = json.load(f)
    with open(LANGS, encoding="utf-8") as f:
        languages = json.load(f)

    only = sys.argv[1:] if len(sys.argv) > 1 else None

    for lang in languages:
        code = lang["code"]
        if code == "en":
            continue
        if only and code not in only:
            continue

        path = LOC / f"{code}.json"
        with open(path, encoding="utf-8") as f:
            loc = json.load(f)

        missing = [k for k in en if k not in loc]
        if not missing:
            print(f"{code}: up to date")
            continue

        print(f"{code}: translating {len(missing)} keys …")
        for i in range(0, len(missing), BATCH_SIZE):
            batch_keys = missing[i : i + BATCH_SIZE]
            subset = {k: en[k] for k in batch_keys}
            translated = openrouter_translate(api_key, lang, subset)
            for k in batch_keys:
                if k in translated:
                    loc[k] = translated[k]
                else:
                    loc[k] = en[k]
            path.write_text(json.dumps(loc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"  batch {i // BATCH_SIZE + 1}: saved {len(batch_keys)} keys")
            time.sleep(3)

        time.sleep(SLEEP_BETWEEN_LANGS)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
