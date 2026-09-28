import SwiftUI

struct MainTabView: View {
    @StateObject private var vm = CameraViewModel()
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CoachView(vm: vm)
                .tabItem { Label(languageManager.text("tab_coach"), systemImage: "waveform.path.ecg") }
                .tag(0)

            EmergencyView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label(languageManager.text("tab_emergency"), systemImage: "cross.case.fill") }
                .tag(1)

            TrainingView(vm: vm)
                .tabItem { Label(languageManager.text("tab_learn"), systemImage: "book.fill") }
                .tag(2)

            AIAssistantView(vm: vm)
                .tabItem { Label(languageManager.text("tab_ai"), systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(3)

            MoreView()
                .tabItem { Label(languageManager.text("tab_more"), systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
        .tint(.red)
        .id(languageManager.localeRevision)
        .onAppear {
            vm.configure()
            vm.bindSpeechToEmergencyFlow()
            vm.aiCoach.appendSystemWelcome()
        }
        .onChange(of: languageManager.current.code) { _, _ in
            vm.syncLanguage()
            vm.refreshLocalizedStrings()
            vm.emergencyFlow.reset()
            vm.emergencyFlow.refreshLLMStatus()
            vm.aiCoach.refreshSystemPrompt()
            vm.aiCoach.reset()
        }
    }
}
