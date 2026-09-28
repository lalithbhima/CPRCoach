import SwiftUI

@main
struct VisionCPRCoachApp: App {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.locale)
        }
    }
}
