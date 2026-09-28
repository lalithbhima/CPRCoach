import Foundation

enum AppConfig {
    static let googleMapsKeyStorageKey = "VisionCPRCoach.GoogleMapsAPIKey"
    static let calibrationStorageKey = "VisionCPRCoach.CalibrationProfile"
    static let languageCodeKey = "VisionCPRCoach.LanguageCode"
    static let onboardingCompleteKey = "VisionCPRCoach.OnboardingComplete"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompleteKey) }
    }

    static var googleMapsAPIKey: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: googleMapsKeyStorageKey)
            return stored?.isEmpty == false ? stored : ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"]
        }
        set { UserDefaults.standard.set(newValue, forKey: googleMapsKeyStorageKey) }
    }

    static func loadCalibration() -> CalibrationProfile {
        guard let data = UserDefaults.standard.data(forKey: calibrationStorageKey),
              let profile = try? JSONDecoder().decode(CalibrationProfile.self, from: data) else {
            return .default
        }
        return profile
    }

    static func saveCalibration(_ profile: CalibrationProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: calibrationStorageKey)
        }
    }
}
