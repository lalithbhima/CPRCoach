import Foundation
import Combine

struct AppLanguage: Identifiable, Codable, Equatable, Hashable {
    let code: String
    let name: String
    let native: String
    let flag: String
    let speech: String

    var id: String { code }
    /// e.g. తెలుగు (Telugu)
    var displayName: String { "\(native) (\(name))" }
    var pickerLabel: String { "\(flag) \(native) (\(name))" }
}

/// Multilingual support — UI strings + TTS/STT locale codes.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var current: AppLanguage
    @Published private(set) var languages: [AppLanguage] = []
    @Published private(set) var strings: [String: String] = [:]
    @Published private(set) var localeRevision = 0

    var locale: Locale { Locale(identifier: resolvedSpeechCode) }
    var speechCode: String { current.speech }

    /// Speech locale actually used on this device (may fall back if Apple STT unavailable).
    var resolvedSpeechCode: String {
        SpeechLocaleResolver.resolve(
            preferredSpeechCode: current.speech,
            languageCode: current.code
        ).localeIdentifier
    }

    var voiceLanguageCode: String {
        SpeechLocaleResolver.resolveVoiceLanguage(preferredSpeechCode: current.speech)
    }

    private var allLocalizations: [String: [String: String]] = [:]

    private init() {
        let defaultLang = AppLanguage(code: "en", name: "English", native: "English", flag: "🇺🇸", speech: "en-US")
        current = defaultLang

        loadLanguages()
        loadLocalizations()

        let savedCode = UserDefaults.standard.string(forKey: AppConfig.languageCodeKey) ?? "en"
        if let saved = languages.first(where: { $0.code == savedCode }) {
            current = saved
        } else if let first = languages.first {
            current = first
        }
        applyLanguage(current)
    }

    func setLanguage(_ language: AppLanguage) {
        current = language
        UserDefaults.standard.set(language.code, forKey: AppConfig.languageCodeKey)
        applyLanguage(language)
        localeRevision += 1
    }

    func text(_ key: String) -> String {
        strings[key] ?? allLocalizations["en"]?[key] ?? key
    }

    func textFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func localizedFeedback(_ key: String) -> String {
        text(key)
    }

    func handPlacement(_ placement: HandPlacement) -> String {
        switch placement {
        case .centered: return text("placement_centered")
        case .tooFarLeft: return text("placement_left")
        case .tooFarRight: return text("placement_right")
        case .tooHigh: return text("placement_high")
        case .tooLow: return text("placement_low")
        case .unknown: return text("placement_unknown")
        }
    }

    func compressionQuality(_ quality: CompressionQuality) -> String {
        switch quality {
        case .excellent: return text("quality_excellent")
        case .good: return text("quality_good")
        case .needsWork: return text("quality_needs_work")
        case .poor: return text("quality_poor")
        case .unknown: return text("quality_unknown")
        }
    }

    func depthQuality(_ depth: DepthEstimate) -> String {
        switch depth {
        case .adequate: return text("depth_adequate")
        case .tooShallow: return text("depth_shallow")
        case .tooDeep: return text("depth_deep")
        case .unknown: return text("depth_unknown")
        }
    }

    func recoilQuality(_ recoil: RecoilQuality) -> String {
        switch recoil {
        case .full: return text("recoil_full")
        case .incomplete: return text("recoil_incomplete")
        case .unknown: return text("recoil_unknown")
        }
    }

    func flowState(_ state: CPRFlowState) -> String {
        switch state {
        case .ready: return text("flow_ready")
        case .checkResponsiveness: return text("flow_responsive")
        case .checkBreathing: return text("flow_breathing")
        case .callEmergency: return text("flow_call")
        case .startCompressions: return text("flow_compressions")
        case .activeCoaching: return text("flow_active")
        case .paused: return text("flow_paused")
        case .finished: return text("flow_finished")
        }
    }

    func guidedStep(_ step: EmergencyGuidedFlowEngine.Step) -> String {
        text("guided_step_\(step.rawValue)")
    }

    /// Pipe-separated speech intent tokens for the emergency guided flow (e.g. `yes|yeah|అవును`).
    func nlpTokens(_ key: String) -> [String] {
        let raw = text(key)
        guard raw != key, !raw.isEmpty else { return [] }
        return raw
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func applyLanguage(_ language: AppLanguage) {
        let english = allLocalizations["en"] ?? [:]
        let langStrings = allLocalizations[language.code] ?? [:]
        // Per-locale JSON files are complete — use them directly.
        if langStrings.count >= english.count {
            strings = langStrings
        } else {
            strings = english.merging(langStrings) { _, new in new }
        }
    }

    private func loadLanguages() {
        guard let url = Bundle.main.url(forResource: "languages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AppLanguage].self, from: data) else {
            languages = [AppLanguage(code: "en", name: "English", native: "English", flag: "🇺🇸", speech: "en-US")]
            return
        }
        languages = decoded
    }

    private func loadLocalizations() {
        var loaded: [String: [String: String]] = [:]

        if let english = loadLocaleFromBundle(code: "en") {
            loaded["en"] = english
        }

        for language in languages {
            let code = language.code
            if code == "en" { continue }
            if let file = loadLocaleFromBundle(code: code) {
                loaded[code] = file
            }
        }

        if loaded.isEmpty {
            loadLegacyLocalizations()
            return
        }
        allLocalizations = loaded
    }

    /// Locale JSON files are copied flat into the app bundle (e.g. `te.json` at bundle root).
    private func loadLocaleFromBundle(code: String) -> [String: String]? {
        let candidates = [
            Bundle.main.url(forResource: code, withExtension: "json"),
            Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Localizations"),
            Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Resources/Localizations")
        ]
        for url in candidates.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                continue
            }
            return decoded
        }
        return nil
    }

    private func loadLegacyLocalizations() {
        guard let url = Bundle.main.url(forResource: "localizations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            return
        }
        allLocalizations = decoded
    }
}

enum L10n {
    @MainActor static var lang: LanguageManager { LanguageManager.shared }

    @MainActor static func t(_ key: String) -> String {
        lang.text(key)
    }
}
