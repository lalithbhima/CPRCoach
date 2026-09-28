#!/usr/bin/env python3
"""Merge nlp_* speech-intent keys into every locale file."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "VisionCPRCoach" / "Resources" / "Localizations"

# Native yes/no/age/emergency tokens per language (+ keep English loanwords users often say).
NLP: dict[str, dict[str, str]] = {
    "te": {
        "nlp_yes": "అవును|ఆ|సరే|అలాగే|చేసాను|పిలిచాను|సిద్ధం|ready|yes|ok|okay",
        "nlp_no": "లేదు|కాదు|వద్దు|no|nope",
        "nlp_unsure": "తెలియదు|నాకు తెలియదు|ఖచ్చితంగా తెలియదు|not sure",
        "nlp_emergency": "అత్యవసరం|సహాయం|పడిపోయింది|అపస్మారక|గుండెపోటు|emergency|help",
        "nlp_responsive": "స్పందిస్తున్నాడు|కదులుతున్నాడు|జవాబు ఇచ్చాడు|స్పృహలో|conscious|moving",
        "nlp_unresponsive": "స్పందించడం లేదు|స్పందన లేదు|అపస్మారక|పడిపోయింది|unconscious",
        "nlp_breathing": "శ్వాస|ఊపిరి|శ్వాసిస్తున్నాడు|breathing|breath",
        "nlp_not_breathing": "శ్వాస లేదు|ఊపిరి లేదు|శ్వాసించడం లేదు|not breathing",
        "nlp_gasping": "గ్యాస్ప్|ఆకులుకు శ్వాస|gasping|gasp",
        "nlp_called_ems": "పిలిచాను|కాల్ చేసాను|ఫోన్|112|911|అంబులెన్స్|called",
        "nlp_cant_call": "కాల్ చేయలేను|ఫోన్ లేదు|ఒంటరిగా|alone|no phone",
        "nlp_stop_cpr": "ఆపండి|ఆపాలా|మేల్కొన్నాడు|శ్వాస తీసుకుంటున్నాడు|stop cpr",
        "nlp_question": "ఏమి|ఎలా|ఎందుకు|ఎప్పుడు|ఎక్కడ|చేయాలా|చేయగలనా|what|how|why",
        "nlp_infant": "శిశువు|బిడ్డ|పాప|infant|baby|newborn",
        "nlp_child": "పిల్ల|బాలుడు|బాలిక|child|kid",
        "nlp_adult": "పెద్ద|వయోధికుడు|మనిషి|adult|man|woman",
    },
    "hi": {
        "nlp_yes": "हाँ|हां|जी|ठीक|हो गया|कॉल कर दिया|ready|yes|ok",
        "nlp_no": "नहीं|ना|no|nope",
        "nlp_unsure": "पता नहीं|यकीन नहीं|not sure|don't know",
        "nlp_emergency": "आपातकाल|मदद|बेहोश|दिल का दौरा|emergency|help",
        "nlp_responsive": "प्रतिक्रिया|हिल रहा|जवाब दिया|होश में|conscious|moving",
        "nlp_unresponsive": "कोई प्रतिक्रिया नहीं|बेहोश|जवाब नहीं|unresponsive|unconscious",
        "nlp_breathing": "साँस|श्वास|सांस ले रहा|breathing|breath",
        "nlp_not_breathing": "साँस नहीं|श्वास नहीं|not breathing",
        "nlp_gasping": "हाँफना|gasping|gasp",
        "nlp_called_ems": "कॉल कर दिया|फोन|112|911|एम्बुलेंस|called",
        "nlp_cant_call": "कॉल नहीं कर सकता|फोन नहीं|अकेला|alone",
        "nlp_stop_cpr": "रोकूं|जाग गया|साँस ले रहा|stop cpr",
        "nlp_question": "क्या|कैसे|क्यों|कब|कहाँ|what|how|why",
        "nlp_infant": "शिशु|बच्चा|नवजात|infant|baby",
        "nlp_child": "बच्चा|बालक|child|kid",
        "nlp_adult": "वयस्क|बड़ा|adult|man|woman",
    },
    "es": {
        "nlp_yes": "sí|si|claro|vale|listo|ya llamé|yes|ok",
        "nlp_no": "no|nop|para nada",
        "nlp_unsure": "no sé|no estoy seguro|not sure",
        "nlp_emergency": "emergencia|ayuda|inconsciente|emergency|help",
        "nlp_responsive": "responde|respondió|se mueve|consciente|conscious",
        "nlp_unresponsive": "no responde|inconsciente|desmayado|unconscious",
        "nlp_breathing": "respira|respiración|aliento|breathing",
        "nlp_not_breathing": "no respira|sin respiración|not breathing",
        "nlp_gasping": "jadea|jadeo|gasping",
        "nlp_called_ems": "llamé|teléfono|112|911|ambulancia|called",
        "nlp_cant_call": "no puedo llamar|sin teléfono|solo|alone",
        "nlp_stop_cpr": "parar rcp|despertó|respira|stop cpr",
        "nlp_question": "qué|cómo|por qué|cuándo|dónde|what|how",
        "nlp_infant": "bebé|infante|recién nacido|infant|baby",
        "nlp_child": "niño|niña|child|kid",
        "nlp_adult": "adulto|hombre|mujer|adult",
    },
}

def main() -> None:
    en = json.load(open(LOC / "en.json", encoding="utf-8"))
    nlp_keys = [k for k in en if k.startswith("nlp_")]
    for path in sorted(LOC.glob("*.json")):
        if path.name in ("localizations.json",):
            continue
        code = path.stem
        data = json.load(open(path, encoding="utf-8"))
        if code in NLP:
            data.update(NLP[code])
        else:
            for k in nlp_keys:
                if k not in data:
                    data[k] = en[k]
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(code, "nlp ok")

if __name__ == "__main__":
    main()
