import Foundation
import Speech
import AVFoundation

/// Picks a speech locale that Apple actually supports for dictation on this device.
enum SpeechLocaleResolver {
    struct Resolution {
        let localeIdentifier: String
        let usedFallback: Bool
    }

    /// Ordered fallbacks when the preferred BCP-47 tag is unavailable offline.
    private static let alternateChains: [String: [String]] = [
        "te": ["te-IN", "hi-IN", "en-IN", "en-US"],
        "ta": ["ta-IN", "hi-IN", "en-IN", "en-US"],
        "bn": ["bn-IN", "hi-IN", "en-IN", "en-US"],
        "mr": ["mr-IN", "hi-IN", "en-IN", "en-US"],
        "pa": ["pa-IN", "hi-IN", "en-IN", "en-US"],
        "ur": ["ur-PK", "ur-IN", "hi-IN", "en-US"],
        "hi": ["hi-IN", "en-IN", "en-US"],
        "fil": ["fil-PH", "tl-PH", "en-PH", "en-US"],
        "no": ["nb-NO", "no-NO", "en-US"],
        "zh-Hans": ["zh-CN", "zh-Hans-CN", "en-US"],
        "zh-Hant": ["zh-TW", "zh-HK", "zh-Hant-TW", "en-US"],
        "pt-BR": ["pt-BR", "pt-PT", "en-US"],
        "sr": ["sr-RS", "sr-Latn-RS", "en-US"],
    ]

    static func resolve(preferredSpeechCode: String, languageCode: String) -> Resolution {
        var candidates: [String] = []
        func append(_ id: String) {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        append(preferredSpeechCode)
        for id in alternateChains[languageCode] ?? [] {
            append(id)
        }

        let base = preferredSpeechCode.split(separator: "-").first.map(String.init) ?? languageCode
        append("\(base)-US")
        append("en-US")

        for id in candidates {
            if isAvailable(id) {
                return Resolution(localeIdentifier: id, usedFallback: id != preferredSpeechCode)
            }
        }

        return Resolution(localeIdentifier: "en-US", usedFallback: preferredSpeechCode != "en-US")
    }

    static func isAvailable(_ localeIdentifier: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            return false
        }
        return recognizer.isAvailable
    }

    static func resolveVoiceLanguage(preferredSpeechCode: String) -> String {
        if AVSpeechSynthesisVoice(language: preferredSpeechCode) != nil {
            return preferredSpeechCode
        }
        let base = preferredSpeechCode.split(separator: "-").first.map(String.init) ?? "en"
        if let voice = AVSpeechSynthesisVoice(language: base) {
            return voice.language
        }
        return "en-US"
    }
}
