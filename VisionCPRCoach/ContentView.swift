import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var onboardingComplete = AppConfig.hasCompletedOnboarding
    @State private var welcomeComplete = false

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingLanguageView(isComplete: $onboardingComplete)
            } else if !welcomeComplete {
                WelcomeView(isComplete: $welcomeComplete)
            } else {
                MainTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, languageManager.locale)
        .animation(.easeInOut(duration: 0.25), value: languageManager.localeRevision)
    }
}
