import SwiftUI

struct OnboardingLanguageView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Binding var isComplete: Bool
    @State private var searchText = ""

    private var filteredLanguages: [AppLanguage] {
        if searchText.isEmpty { return languageManager.languages }
        return languageManager.languages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.native.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            BubbleBackground().ignoresSafeArea()

            VStack(spacing: 20) {
                HeroHeader(
                    title: languageManager.text("select_language"),
                    subtitle: languageManager.text("onboarding_subtitle"),
                    icon: "globe"
                )
                .padding(.horizontal, 20)
                .padding(.top, 24)

                TextField(languageManager.text("search_languages"), text: $searchText)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredLanguages) { language in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    languageManager.setLanguage(language)
                                }
                            } label: {
                                HStack {
                                    Text(language.pickerLabel)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if language.code == languageManager.current.code {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(language.code == languageManager.current.code
                                              ? Color.red.opacity(0.1)
                                              : Color.white.opacity(0.75))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    AppConfig.hasCompletedOnboarding = true
                    isComplete = true
                } label: {
                    Text(languageManager.text("continue_btn"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryBubbleButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
