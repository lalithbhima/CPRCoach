#!/usr/bin/env python3
"""Apply welcome screen translations to all 45 locale files."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "VisionCPRCoach" / "Resources" / "Localizations"

WELCOME: dict[str, dict[str, str]] = {
    "en": {
        "welcome_title": "Welcome",
        "welcome_subtitle": "Emergency voice guidance and hands-on training — all in one place.",
        "welcome_button": "Welcome to CPR Coach",
    },
    "es": {
        "welcome_title": "Bienvenido",
        "welcome_subtitle": "Guía de voz de emergencia y formación práctica — todo en un solo lugar.",
        "welcome_button": "Bienvenido",
    },
    "fr": {
        "welcome_title": "Bienvenue",
        "welcome_subtitle": "Assistance vocale d'urgence et formation pratique — tout en un seul endroit.",
        "welcome_button": "Bienvenue",
    },
    "de": {
        "welcome_title": "Willkommen",
        "welcome_subtitle": "Notfall-Sprachführung und praktisches Training — alles an einem Ort.",
        "welcome_button": "Willkommen",
    },
    "it": {
        "welcome_title": "Benvenuto",
        "welcome_subtitle": "Guida vocale di emergenza e formazione pratica — tutto in un unico posto.",
        "welcome_button": "Benvenuto",
    },
    "pt": {
        "welcome_title": "Bem-vindo",
        "welcome_subtitle": "Orientação de voz de emergência e formação prática — tudo num só lugar.",
        "welcome_button": "Bem-vindo",
    },
    "pt-BR": {
        "welcome_title": "Bem-vindo",
        "welcome_subtitle": "Orientação de voz de emergência e treinamento prático — tudo em um só lugar.",
        "welcome_button": "Bem-vindo",
    },
    "zh-Hans": {
        "welcome_title": "欢迎",
        "welcome_subtitle": "紧急语音引导和实操培训——尽在一处。",
        "welcome_button": "欢迎",
    },
    "zh-Hant": {
        "welcome_title": "歡迎",
        "welcome_subtitle": "緊急語音引導和實作訓練——盡在一處。",
        "welcome_button": "歡迎",
    },
    "ja": {
        "welcome_title": "ようこそ",
        "welcome_subtitle": "緊急音声ガイドと実践トレーニング — すべてが一つに。",
        "welcome_button": "ようこそ",
    },
    "ko": {
        "welcome_title": "환영합니다",
        "welcome_subtitle": "응급 음성 안내와 실습 훈련 — 모두 한곳에서.",
        "welcome_button": "환영합니다",
    },
    "ar": {
        "welcome_title": "مرحباً",
        "welcome_subtitle": "إرشاد صوتي للطوارئ وتدريب عملي — كل ذلك في مكان واحد.",
        "welcome_button": "مرحباً",
    },
    "hi": {
        "welcome_title": "स्वागत है",
        "welcome_subtitle": "आपातकालीन वॉयस मार्गदर्शन और व्यावहारिक प्रशिक्षण — सब एक ही जगह।",
        "welcome_button": "स्वागत है",
    },
    "ru": {
        "welcome_title": "Добро пожаловать",
        "welcome_subtitle": "Экстренное голосовое сопровождение и практическое обучение — всё в одном месте.",
        "welcome_button": "Добро пожаловать",
    },
    "uk": {
        "welcome_title": "Ласкаво просимо",
        "welcome_subtitle": "Екстрений голосовий супровід і практичні тренування — усе в одному місці.",
        "welcome_button": "Ласкаво просимо",
    },
    "pl": {
        "welcome_title": "Witamy",
        "welcome_subtitle": "Głosowe wsparcie w nagłych wypadkach i szkolenie praktyczne — wszystko w jednym miejscu.",
        "welcome_button": "Witamy",
    },
    "nl": {
        "welcome_title": "Welkom",
        "welcome_subtitle": "Nood-stembegeleiding en praktische training — alles op één plek.",
        "welcome_button": "Welkom",
    },
    "sv": {
        "welcome_title": "Välkommen",
        "welcome_subtitle": "Röststöd vid nödsituationer och praktisk träning — allt på ett ställe.",
        "welcome_button": "Välkommen",
    },
    "no": {
        "welcome_title": "Velkommen",
        "welcome_subtitle": "Nødstemmeveiledning og praktisk opplæring — alt på ett sted.",
        "welcome_button": "Velkommen",
    },
    "da": {
        "welcome_title": "Velkommen",
        "welcome_subtitle": "Nødstemmevejledning og praktisk træning — alt ét sted.",
        "welcome_button": "Velkommen",
    },
    "fi": {
        "welcome_title": "Tervetuloa",
        "welcome_subtitle": "Hätäpuheohjaus ja käytännön harjoittelu — kaikki yhdessä paikassa.",
        "welcome_button": "Tervetuloa",
    },
    "tr": {
        "welcome_title": "Hoş geldiniz",
        "welcome_subtitle": "Acil sesli rehberlik ve uygulamalı eğitim — hepsi tek yerde.",
        "welcome_button": "Hoş geldiniz",
    },
    "el": {
        "welcome_title": "Καλώς ήρθατε",
        "welcome_subtitle": "Φωνητική βοήθεια έκτακτης ανάγκης και πρακτική εκπαίδευση — όλα σε ένα μέρος.",
        "welcome_button": "Καλώς ήρθατε",
    },
    "cs": {
        "welcome_title": "Vítejte",
        "welcome_subtitle": "Hlasové nouzové vedení a praktické školení — vše na jednom místě.",
        "welcome_button": "Vítejte",
    },
    "ro": {
        "welcome_title": "Bun venit",
        "welcome_subtitle": "Ghidare vocală de urgență și instruire practică — totul într-un singur loc.",
        "welcome_button": "Bun venit",
    },
    "hu": {
        "welcome_title": "Üdvözöljük",
        "welcome_subtitle": "Vészhelyzeti hangos útmutatás és gyakorlati képzés — minden egy helyen.",
        "welcome_button": "Üdvözöljük",
    },
    "he": {
        "welcome_title": "ברוכים הבאים",
        "welcome_subtitle": "הנחיה קולית לחירום ואימון מעשי — הכל במקום אחד.",
        "welcome_button": "ברוכים הבאים",
    },
    "fa": {
        "welcome_title": "خوش آمدید",
        "welcome_subtitle": "راهنمایی صوتی اضطراری و آموزش عملی — همه در یکجا.",
        "welcome_button": "خوش آمدید",
    },
    "vi": {
        "welcome_title": "Chào mừng",
        "welcome_subtitle": "Hướng dẫn giọng nói khẩn cấp và đào tạo thực hành — tất cả trong một nơi.",
        "welcome_button": "Chào mừng",
    },
    "th": {
        "welcome_title": "ยินดีต้อนรับ",
        "welcome_subtitle": "คำแนะนำเสียงฉุกเฉิน และการฝึกปฏิบัติ — ทั้งหมดในที่เดียว",
        "welcome_button": "ยินดีต้อนรับ",
    },
    "id": {
        "welcome_title": "Selamat datang",
        "welcome_subtitle": "Panduan suara darurat dan latihan praktis — semuanya dalam satu tempat.",
        "welcome_button": "Selamat datang",
    },
    "ms": {
        "welcome_title": "Selamat datang",
        "welcome_subtitle": "Panduan suara kecemasan dan latihan praktikal — semuanya di satu tempat.",
        "welcome_button": "Selamat datang",
    },
    "fil": {
        "welcome_title": "Maligayang pagdating",
        "welcome_subtitle": "Gabay sa boses sa emergency at hands-on na pagsasanay — lahat sa isang lugar.",
        "welcome_button": "Maligayang pagdating",
    },
    "bn": {
        "welcome_title": "স্বাগতম",
        "welcome_subtitle": "জরুরি ভয়েস গাইডেন্স এবং হাতে-কলমে প্রশিক্ষণ — সব এক জায়গায়।",
        "welcome_button": "স্বাগতম",
    },
    "ta": {
        "welcome_title": "வரவேற்கிறோம்",
        "welcome_subtitle": "அவசர குரல் வழிகாட்டுதல் மற்றும் பயிற்சி — அனைத்தும் ஒரே இடத்தில்.",
        "welcome_button": "வரவேற்கிறோம்",
    },
    "te": {
        "welcome_title": "స్వాగతం",
        "welcome_subtitle": "అత్యవసర వాయిస్ మార్గదర్శకత్వం మరియు ప్రాక్టికల్ శిక్షణ — అన్నీ ఒకే చోట.",
        "welcome_button": "స్వాగతం",
    },
    "mr": {
        "welcome_title": "स्वागत आहे",
        "welcome_subtitle": "आपत्कालीन व्हॉइस मार्गदर्शन आणि प्रात्यक्षिक प्रशिक्षण — सर्व एकाच ठिकाणी.",
        "welcome_button": "स्वागत आहे",
    },
    "ur": {
        "welcome_title": "خوش آمدید",
        "welcome_subtitle": "ایمرجنسی وائس رہنمائی اور عملی تربیت — سب ایک جگہ۔",
        "welcome_button": "خوش آمدید",
    },
    "sw": {
        "welcome_title": "Karibu",
        "welcome_subtitle": "Mwongozo wa sauti wa dharura na mafunzo ya vitendo — yote mahali pamoja.",
        "welcome_button": "Karibu",
    },
    "ca": {
        "welcome_title": "Benvingut",
        "welcome_subtitle": "Guia de veu d'emergència i formació pràctica — tot en un sol lloc.",
        "welcome_button": "Benvingut",
    },
    "sk": {
        "welcome_title": "Vitajte",
        "welcome_subtitle": "Núdzové hlasové vedenie a praktické školenie — všetko na jednom mieste.",
        "welcome_button": "Vitajte",
    },
    "hr": {
        "welcome_title": "Dobrodošli",
        "welcome_subtitle": "Glasovne upute u hitnim slučajevima i praktična obuka — sve na jednom mjestu.",
        "welcome_button": "Dobrodošli",
    },
    "sr": {
        "welcome_title": "Добродошли",
        "welcome_subtitle": "Гласовно упутство у хитним случајевима и практична обука — све на једном месту.",
        "welcome_button": "Добродошли",
    },
    "bg": {
        "welcome_title": "Добре дошли",
        "welcome_subtitle": "Гласово ръководство при спешни случаи и практическо обучение — всичко на едно място.",
        "welcome_button": "Добре дошли",
    },
    "pa": {
        "welcome_title": "ਜੀ ਆਇਆਂ ਨੂੰ",
        "welcome_subtitle": "ਐਮਰਜੈਂਸੀ ਵੌਇਸ ਗਾਈਡੈਂਸ ਅਤੇ ਹੱਥੋਂ-ਕਰਕੇ ਸਿਖਲਾਈ — ਸਭ ਇੱਕ ਥਾਂ ਤੇ।",
        "welcome_button": "ਜੀ ਆਇਆਂ ਨੂੰ",
    },
}


def main() -> None:
    missing = []
    for code, strings in WELCOME.items():
        path = LOC / f"{code}.json"
        if not path.exists():
            missing.append(code)
            continue
        data = json.load(open(path, encoding="utf-8"))
        data.update(strings)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"updated {code}")

    if missing:
        raise SystemExit(f"Missing locale files: {missing}")

    # Verify all 45 languages from languages.json
    langs = json.load(open(ROOT / "VisionCPRCoach" / "Resources" / "languages.json"))
    en = WELCOME["en"]
    errors = []
    for lang in langs:
        code = lang["code"]
        path = LOC / f"{code}.json"
        data = json.load(open(path, encoding="utf-8"))
        for key in ("welcome_title", "welcome_subtitle", "welcome_button"):
            if data.get(key) == en.get(key) and code != "en":
                errors.append(f"{code}.{key} still English")
    if errors:
        print("WARN:", len(errors), "keys still English")
        for e in errors[:5]:
            print(" ", e)
    else:
        print("OK: all 45 languages have translated welcome strings")


if __name__ == "__main__":
    main()
