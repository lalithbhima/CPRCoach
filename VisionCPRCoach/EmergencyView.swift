import SwiftUI

struct EmergencyView: View {
    @ObservedObject var vm: CameraViewModel
    @Binding var selectedTab: Int
    @EnvironmentObject private var languageManager: LanguageManager
    @ObservedObject private var emergencyNumbers = EmergencyNumberService.shared
    @State private var showEmergencyCallConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                BubbleBackground().ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        HeroHeader(
                            title: languageManager.text("emergency_title"),
                            subtitle: languageManager.text("emergency_subtitle"),
                            icon: "cross.case.fill"
                        )

                        voiceAIStatusCard
                        llmStatusBadge
                        voiceAIButton
                        quickActions
                        conversationLog
                        disclaimer
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(languageManager.text("tab_emergency"))
            .onAppear {
                vm.emergencyFlow.refreshLLMStatus()
                emergencyNumbers.refreshFromLocationIfAuthorized()
            }
            .emergencyCallConfirmation(
                isPresented: $showEmergencyCallConfirm,
                number: emergencyNumbers.emergencyNumber,
                languageManager: languageManager
            )
        }
    }

    private var voiceAIStatusCard: some View {
        FloatingBubbleCard(accent: vm.emergencyFlow.isVoiceAIActive ? .red : .purple) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(languageManager.text("emergency_voice_ai_title"))
                        .font(.headline)

                    Text(vm.emergencyFlow.guidanceMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if vm.emergencyFlow.isVoiceAIActive, vm.speechRecognition.isListening {
                        Text(vm.speechRecognition.transcript.isEmpty
                             ? languageManager.text("speak_now")
                             : vm.speechRecognition.transcript)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }

                Spacer(minLength: 8)

                VoiceOrb(
                    isOn: vm.emergencyFlow.isVoiceAIActive,
                    isLive: vm.speechRecognition.isListening
                        || vm.voiceCoach.isSpeaking
                        || vm.emergencyFlow.isProcessing,
                    label: ""
                )
            }
        }
    }

    private var llmStatusBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.green)
                Text(vm.emergencyFlow.llmStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if vm.emergencyFlow.isVoiceAIActive, !vm.emergencyFlow.currentGuidedStep.isEmpty {
                Text("\(languageManager.text("guided_step_label")): \(languageManager.flowState(vm.emergencyFlow.flowState))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var voiceAIButton: some View {
        Button {
            vm.toggleEmergencyVoiceAI()
        } label: {
            Label(
                vm.emergencyFlow.isVoiceAIActive
                    ? languageManager.text("emergency_voice_ai_end")
                    : languageManager.text("emergency_voice_ai"),
                systemImage: vm.emergencyFlow.isVoiceAIActive ? "stop.circle.fill" : "mic.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryBubbleButtonStyle())
        .disabled(vm.emergencyFlow.isProcessing && !vm.emergencyFlow.isVoiceAIActive)
    }

    private var conversationLog: some View {
        Group {
            if vm.emergencyFlow.isVoiceAIActive
                || !vm.emergencyFlow.conversationLog.isEmpty
                || vm.emergencyFlow.sessionSummary != nil {
                FloatingBubbleCard(accent: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(languageManager.text("voice_conversation"))
                            .font(.headline)

                        if vm.emergencyFlow.conversationLog.isEmpty {
                            Text(languageManager.text("emergency_conv_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.emergencyFlow.conversationLog) { message in
                                HStack {
                                    if message.role == .user { Spacer() }
                                    Text(message.text)
                                        .font(.subheadline)
                                        .padding(12)
                                        .background(
                                            message.role == .user
                                                ? Color.red.opacity(0.12)
                                                : Color(.tertiarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        )
                                    if message.role == .coach { Spacer() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                showEmergencyCallConfirm = true
            } label: {
                Label(
                    languageManager.textFormat("call_emergency_button", emergencyNumbers.emergencyNumber),
                    systemImage: "phone.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryBubbleButtonStyle())

            Button { selectedTab = 4 } label: {
                LocLabel(key: "find_hospital", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryBubbleButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private var disclaimer: some View {
        Text(CPRGuidelines.disclaimer)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
