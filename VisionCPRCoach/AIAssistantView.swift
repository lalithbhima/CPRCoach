import SwiftUI

struct AIAssistantView: View {
    @ObservedObject var vm: CameraViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BubbleBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    if !vm.aiCoach.isLiveLLMReady {
                        apiKeyBanner
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(vm.aiCoach.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                if vm.aiCoach.isProcessing {
                                    ProgressView(languageManager.text("chatcpr_thinking"))
                                        .padding()
                                }
                            }
                            .padding(16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: vm.aiCoach.messages.count) { _, _ in
                            if let last = vm.aiCoach.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    liveMetricsBanner
                    suggestionChips

                    HStack(spacing: 10) {
                        TextField(languageManager.text("chatcpr_placeholder"), text: $inputText, axis: .vertical)
                            .focused($isInputFocused)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            .lineLimit(1...5)
                            .submitLabel(.send)
                            .onSubmit(sendMessage)

                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red)
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.aiCoach.isProcessing)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                }
                .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            }
            .navigationTitle(languageManager.text("chatcpr_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(languageManager.text("ai_clear")) { vm.aiCoach.reset() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(languageManager.text("step_done")) { isInputFocused = false }
                }
            }
        }
    }

    private var apiKeyBanner: some View {
        Text(languageManager.text("chatcpr_no_api_key"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.12))
    }

    private var suggestionChips: some View {
        let keys = ["ai_suggest_1", "ai_suggest_2", "ai_suggest_3", "ai_suggest_4"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    let text = languageManager.text(key)
                    Button {
                        inputText = text
                        sendMessage()
                    } label: {
                        Text(text)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 1))
                            .foregroundStyle(.red)
                    }
                    .disabled(vm.aiCoach.isProcessing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var liveMetricsBanner: some View {
        Group {
            if vm.isRunning, let metrics = vm.latestMetrics {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(languageManager.text("ai_joints_live")) · \(Int(metrics.compressionsPerMinute)) CPM · \(String(format: "%.1f", metrics.estimatedDepthCm)) cm")
                            .font(.caption.weight(.semibold))
                        Text(vm.voiceEngine.lastAnalysisSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(languageManager.text("ai_analyze_form")) {
                        inputText = languageManager.text("ai_analyze_form")
                        sendMessage()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.07))
            }
        }
    }

    private func sendMessage() {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        inputText = ""
        Task {
            await vm.aiCoach.ask(
                text,
                liveMetrics: vm.latestMetrics,
                joints: vm.latestJoints
            )
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 36) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(14)
                    .background(
                        isUser
                            ? LinearGradient(colors: [.red, .red.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.secondarySystemGroupedBackground)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .shadow(color: isUser ? .red.opacity(0.15) : .clear, radius: 8, y: 4)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isUser { Spacer(minLength: 36) }
        }
    }
}
