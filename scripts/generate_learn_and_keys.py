#!/usr/bin/env python3
"""Translate learn modules + new locale keys into all languages via OpenRouter."""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "VisionCPRCoach" / "Resources"
LOC = RES / "Localizations"
LEARN = RES / "Learn"
LANGS = RES / "languages.json"
SECRET = ROOT / "Config" / "secret.ts"
MODEL = "openrouter/free"

NEW_KEYS = [
    "guided_step_confirmEmergency",
    "guided_step_victimAge",
    "guided_step_sceneSafe",
    "guided_step_checkResponsive",
    "guided_step_checkBreathing",
    "guided_step_call911",
    "guided_step_confirm911",
    "guided_step_getAED",
    "guided_step_startCPR",
    "guided_step_activeCoaching",
    "guided_step_recoveryMonitor",
    "guided_step_notEmergency",
    "overlay_align_hands",
]


def load_api_key() -> str:
    if not SECRET.exists():
        raise SystemExit("Missing Config/secret.ts")
    text = SECRET.read_text(encoding="utf-8")
    m = re.search(r'OPENROUTER_API_KEY\s*=\s*"([^"]+)"', text)
    if not m or not m.group(1).strip():
        raise SystemExit("OPENROUTER_API_KEY not found in secret.ts")
    return m.group(1).strip()


def openrouter_json(api_key: str, system: str, user: str, retries: int = 4) -> dict:
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
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            content = body["choices"][0]["message"]["content"]
            return json.loads(content)
        except (urllib.error.HTTPError, urllib.error.URLError, KeyError, json.JSONDecodeError) as exc:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
            print(f"  retry {attempt + 1} after {exc}")
    raise RuntimeError("unreachable")


def translate_learn(api_key: str, lang: dict, source: dict) -> dict:
    system = (
        "You are a medical-education translator. Translate CPR training JSON into the target language. "
        "Keep ids, icon, and colorName unchanged. Preserve medical accuracy. Return valid JSON only."
    )
    user = (
        f"Target language: {lang['native']} ({lang['name']}), code {lang['code']}.\n"
        f"Translate every user-facing string in this JSON:\n{json.dumps(source, ensure_ascii=False)}"
    )
    return openrouter_json(api_key, system, user)


def translate_keys(api_key: str, lang: dict, en_subset: dict) -> dict:
    system = (
        "Translate UI strings for a CPR app. Return JSON object with the same keys and translated values only."
    )
    user = (
        f"Target: {lang['native']} ({lang['name']}).\n"
        f"Strings:\n{json.dumps(en_subset, ensure_ascii=False)}"
    )
    return openrouter_json(api_key, system, user)


def main() -> int:
    api_key = load_api_key()
    with open(LANGS, encoding="utf-8") as f:
        languages = json.load(f)
    with open(LEARN / "learn_en.json", encoding="utf-8") as f:
        learn_en = json.load(f)
    with open(LOC / "en.json", encoding="utf-8") as f:
        en = json.load(f)
    en_new = {k: en[k] for k in NEW_KEYS}

    LEARN.mkdir(parents=True, exist_ok=True)

    for lang in languages:
        code = lang["code"]
        print(f"== {code} ==")

        learn_path = LEARN / f"learn_{code}.json"
        if code == "en":
            if not learn_path.exists():
                learn_path.write_text(json.dumps(learn_en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        elif not learn_path.exists() or "--force-learn" in sys.argv:
            print("  learn …")
            translated = translate_learn(api_key, lang, learn_en)
            learn_path.write_text(json.dumps(translated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            time.sleep(0.5)
        else:
            print("  learn skip (exists)")

        loc_path = LOC / f"{code}.json"
        with open(loc_path, encoding="utf-8") as f:
            loc = json.load(f)
        missing = [k for k in NEW_KEYS if k not in loc or (code != "en" and loc.get(k) == en.get(k))]
        if code == "en" or not missing:
            for k in NEW_KEYS:
                loc[k] = en[k]
        else:
            print(f"  keys ({len(missing)}) …")
            subset = {k: en[k] for k in missing}
            translated = translate_keys(api_key, lang, subset)
            for k, v in translated.items():
                if k in NEW_KEYS:
                    loc[k] = v
            time.sleep(0.3)
        loc_path.write_text(json.dumps(loc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
