import SwiftUI

/// Full-screen, immersive live-coaching mode. Shown when the user starts training so they can see
/// the camera, the colored skeleton + action recognition, the live metrics and the rhythm guide
/// all at once — with glass controls layered on top.
struct ImmersiveCoachView: View {
    @ObservedObject var vm: CameraViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LiveCoachCameraPreview(
                captureSession: vm.session,
                arSession: vm.arSession,
                usesARPipeline: vm.usesARCameraPipeline,
                rescuer: vm.sceneAnalysis?.overlayRescuer,
                patient: vm.sceneAnalysis?.patient,
                showOverlay: vm.showAROverlay,
                frameWidth: vm.sceneAnalysis?.moveNetPose?.frameWidth ?? 0,
                frameHeight: vm.sceneAnalysis?.moveNetPose?.frameHeight ?? 0,
                onViewportSizeChange: { vm.updateARViewportSize($0) }
            )
                .ignoresSafeArea()

            // Subtle top/bottom scrims so glass controls stay legible over any scene.
            VStack {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            if !vm.isRunning { vm.startSession() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            GlassIconButton(systemName: "xmark") {
                vm.stopSession()
                isPresented = false
            }

            Spacer()

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(vm.isRunning ? .red : .gray).frame(width: 8, height: 8)
                    Text(vm.isRunning ? languageManager.text("live") : languageManager.text("standby"))
                        .font(.caption.weight(.bold))
                }
                if vm.detectionQuality > 0 {
                    Text("\(languageManager.text("ai_detection")) \(Int(vm.detectionQuality))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if vm.lidarDepthActive {
                    Text(languageManager.text("lidar_depth_badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.cyan.opacity(0.9))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            GlassIconButton(
                systemName: vm.voiceEngine.isVoiceEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill",
                tint: vm.voiceEngine.isVoiceEnabled ? .red : .white
            ) {
                vm.voiceEngine.isVoiceEnabled.toggle()
                if !vm.voiceEngine.isVoiceEnabled { vm.voiceCoach.stop() }
            }
        }
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            // Live coaching line (the same AI voice text spoken aloud).
            if !vm.feedbackMessage.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: vm.voiceCoach.isSpeaking ? "waveform" : "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, isActive: vm.voiceCoach.isSpeaking)
                    Text(vm.feedbackMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            }

            // Metric chips.
            HStack(spacing: 10) {
                ImmersiveMetric(symbol: "metronome.fill", value: "\(Int(vm.compressionsPerMinute))", unit: "CPM", target: "100–120", inRange: vm.compressionsPerMinute >= 100 && vm.compressionsPerMinute <= 120)
                ImmersiveMetric(symbol: "arrow.down.to.line", value: String(format: "%.1f", vm.estimatedDepthCm), unit: "cm", target: "5–6", inRange: vm.depthQuality == .adequate)
                ImmersiveMetric(symbol: "hand.raised.fill", value: handsShort, unit: "", target: nil, inRange: vm.handPlacement == HandPlacement.centered.rawValue)
                ImmersiveMetric(symbol: "gauge.with.dots.needle.67percent", value: "\(Int(vm.pressureScore))", unit: "%", target: nil, inRange: vm.pressureScore >= 75)
            }

            RhythmBar(phase: vm.rhythmPhase, cpm: vm.compressionsPerMinute)

            Button {
                vm.stopSession()
                isPresented = false
            } label: {
                Label(languageManager.text("stop_coaching"), systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryBubbleButtonStyle())
        }
    }

    private var handsShort: String {
        let placement = HandPlacement(rawValue: vm.handPlacement) ?? .unknown
        return placement == .centered
            ? languageManager.text("placement_centered")
            : languageManager.handPlacement(placement)
    }
}

// MARK: - Pieces

struct GlassIconButton: View {
    let systemName: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
        }
    }
}

struct ImmersiveMetric: View {
    let symbol: String
    let value: String
    let unit: String
    let target: String?
    let inRange: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(inRange ? .green : .orange)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            if let target {
                Text(target).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(inRange ? Color.green.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
