import SwiftUI

struct TrainingView: View {
    @ObservedObject var vm: CameraViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var selectedModule: LearnModuleContent?

    private var modules: [LearnModuleContent] {
        LearnModuleContent.modules(for: languageManager)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BubbleBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        HeroHeader(
                            title: languageManager.text("learn_title"),
                            subtitle: languageManager.text("learn_subtitle"),
                            icon: "book.fill"
                        )

                        ForEach(modules) { module in
                            Button {
                                selectedModule = module
                            } label: {
                                FloatingBubbleCard(accent: module.color) {
                                    HStack(spacing: 14) {
                                        Image(systemName: module.icon)
                                            .font(.title2)
                                            .foregroundStyle(module.color)
                                            .frame(width: 44)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(module.title)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(module.summary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        FloatingBubbleCard(accent: .purple) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(languageManager.text("learn_socratic"), systemImage: "brain.head.profile")
                                    .font(.headline)
                                Text(languageManager.text("learn_socratic_hint"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(languageManager.text("tab_learn"))
            .sheet(item: $selectedModule) { module in
                ModuleDetailSheet(module: module, vm: vm)
            }
        }
        .id(languageManager.localeRevision)
    }
}

struct ModuleDetailSheet: View {
    let module: LearnModuleContent
    @ObservedObject var vm: CameraViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var speakingStep: Int?
    @State private var speakingBullet: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(module.overview)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    voiceControls

                    Text(languageManager.text("learn_key_concepts"))
                        .font(.headline)

                    ForEach(Array(module.bullets.enumerated()), id: \.offset) { index, bullet in
                        speakableRow(
                            index: index,
                            text: bullet,
                            isActive: speakingBullet == index,
                            marker: "•"
                        ) {
                            speakBullet(index)
                        }
                    }

                    Text(languageManager.text("learn_steps"))
                        .font(.headline)
                        .padding(.top, 4)

                    ForEach(Array(module.steps.enumerated()), id: \.offset) { index, step in
                        speakableRow(
                            index: index,
                            text: step,
                            isActive: speakingStep == index,
                            marker: "\(index + 1)"
                        ) {
                            speakStep(index)
                        }
                    }
                }
                .padding(20)
            }
            .background(BubbleBackground())
            .navigationTitle(module.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(languageManager.text("learn_done")) {
                        vm.voiceCoach.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { vm.voiceCoach.stop() }
        }
    }

    private var voiceControls: some View {
        HStack(spacing: 12) {
            Button {
                teachWholeLesson()
            } label: {
                Label(languageManager.text("learn_listen"), systemImage: "play.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryBubbleButtonStyle())

            Button {
                vm.voiceCoach.stop()
                speakingStep = nil
                speakingBullet = nil
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func speakableRow(
        index: Int,
        text: String,
        isActive: Bool,
        marker: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(marker)
                    .font(marker == "•" ? .body.bold() : .caption.bold())
                    .frame(width: 28, height: 28)
                    .background(module.color.opacity(isActive ? 0.35 : 0.15), in: Circle())
                    .foregroundStyle(module.color)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isActive ? "waveform" : "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(isActive ? module.color : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? module.color.opacity(0.08) : Color.white.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }

    private func teachWholeLesson() {
        vm.voiceCoach.stop()
        speakingStep = nil
        speakingBullet = nil
        vm.voiceCoach.speak(module.overview, priority: .normal)
        for bullet in module.bullets {
            vm.voiceCoach.speak(bullet, priority: .normal)
        }
        for step in module.steps {
            vm.voiceCoach.speak(step, priority: .normal)
        }
    }

    private func speakBullet(_ index: Int) {
        speakingBullet = index
        speakingStep = nil
        vm.voiceCoach.stop()
        vm.voiceCoach.speak(module.bullets[index], priority: .normal)
    }

    private func speakStep(_ index: Int) {
        speakingStep = index
        speakingBullet = nil
        vm.voiceCoach.stop()
        vm.voiceCoach.speak(module.steps[index], priority: .normal)
    }
}
