// Vision CPR Coach — Main Coach Tab UI (SwiftUI)
// This is the primary screen users see for live CPR coaching.
// It displays the camera feed, live metrics, voice feedback, and session controls.
// All data comes from CameraViewModel (pose detection + CPRMetricsEngine run behind the scenes).

import SwiftUI

struct CoachView: View {
    @ObservedObject var vm: CameraViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var immersive = false

    var body: some View {
        NavigationStack {
            ZStack {
                BubbleBackground().ignoresSafeArea()

                //  Scrollable coach layout: top → bottom 
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        headerSection          // App title + subtitle
                        voiceCoachBubble       // Last spoken coaching phrase
                        cameraCard             // Live camera + pose overlay
                        primaryStatusCard      // Main feedback message + quality pills
                        actionButtonsCard      // Start / Stop / Calibrate / Reset
                        metricsGrid            // CPM, depth, elbow, hands, recoil, motion
                        disclaimerCard         // Training-only disclaimer
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .frame(maxWidth: .infinity)
            }
            // Full-screen immersive coaching mode (camera fills the screen)
            .fullScreenCover(isPresented: $immersive) {
                ImmersiveCoachView(vm: vm, isPresented: $immersive)
                    .environmentObject(languageManager)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(languageManager.text("app_name"))
                        .font(.headline.weight(.semibold))
                }
            }
        }
    }

    //  Voice coach bubble: shows what the AI just said out loud 
    private var voiceCoachBubble: some View {
        Group {
            if !vm.voiceEngine.lastSpokenText.isEmpty {
                FloatingBubbleCard(accent: .red) {
                    HStack(spacing: 12) {
                        VoiceOrb(isActive: vm.voiceCoach.isSpeaking, label: "")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.text("voice_coach"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(vm.voiceEngine.lastSpokenText)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    //  Header: coach tab title and description 
    private var headerSection: some View {
        HeroHeader(
            title: languageManager.text("coach_header_title"),
            subtitle: languageManager.text("coach_header_subtitle"),
            icon: "waveform.path.ecg"
        )
    }

    //  Camera card: live preview + status pills + expand button 
    private var cameraCard: some View {
        GlassCard {
            ZStack(alignment: .topLeading) {
                cameraSurface

                HStack(spacing: 8) {
                    StatusPill(
                        title: vm.isRunning ? languageManager.text("live") : languageManager.text("standby"),
                        systemImage: vm.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle.fill",
                        tint: vm.isRunning ? .red : .secondary
                    )
                    if vm.detectionQuality > 0 {
                        StatusPill(title: "\(languageManager.text("ai_detection")) \(Int(vm.detectionQuality))%", systemImage: "eye.fill", tint: .green)
                    }
                    if vm.aiModelActive {
                        StatusPill(title: languageManager.text("ai_model_badge"), systemImage: "brain.head.profile", tint: .purple)
                    }
                    if vm.lidarDepthActive {
                        StatusPill(title: languageManager.text("lidar_depth_badge"), systemImage: "dot.scope", tint: .cyan)
                    }
                    Spacer(minLength: 0)
                    Button {
                        immersive = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
    }

    //  Camera surface: preview, skeleton overlay, rhythm bar, standby state 
    private var cameraSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.92))

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
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            if vm.sceneAnalysis?.overlayRescuer == nil, vm.sceneAnalysis?.patient == nil, !vm.isRunning {
                standbyOverlay
            }

            // Rhythm bar pulses with current CPM
            VStack {
                Spacer()
                RhythmBar(phase: vm.rhythmPhase, cpm: vm.compressionsPerMinute)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .frame(height: 380)
    }

    //  Shown before session starts: prompt to tap Start 
    private var standbyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.92))
            Text(languageManager.text("camera_ready"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(languageManager.text("camera_ready_hint"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
    }

    //  Primary status: large coaching message + quality / pressure / depth pills 
    private var primaryStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(languageManager.text("current_guidance"))
                        .font(.headline)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(.red)
                }

                Text(vm.feedbackMessage)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    MiniInfoBubble(title: languageManager.text("metric_quality"), value: languageManager.compressionQuality(vm.overallQuality))
                    MiniInfoBubble(title: languageManager.text("metric_pressure"), value: "\(Int(vm.pressureScore))%")
                    MiniInfoBubble(title: languageManager.text("metric_depth"), value: languageManager.depthQuality(vm.depthQuality))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    //  Action buttons: start/stop coaching, calibrate depth, reset session 
    private var actionButtonsCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if vm.isRunning {
                            vm.stopSession()
                        } else {
                            immersive = true   // immersive view starts the session on appear
                        }
                    } label: {
                        Label(
                            vm.isRunning ? languageManager.text("stop_coaching") : languageManager.text("start_coaching"),
                            systemImage: vm.isRunning ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryBubbleButtonStyle())

                    Button {
                        if let metrics = vm.latestMetrics {
                            vm.calibrate(with: metrics)
                        }
                    } label: {
                        Label(languageManager.text("calibrate"), systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryBubbleButtonStyle())
                }

                Button { vm.resetFlow() } label: {
                    Text(languageManager.text("reset_session"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftPlainButtonStyle())
            }
        }
    }

    //  Live metrics grid: all CPR numbers the Python prototype also tracks 
    private var metricsGrid: some View {
        VStack(spacing: 12) {
            HStack {
                Text(languageManager.text("live_metrics"))
                    .font(.headline)
                Spacer()
                Text("\(languageManager.text("confidence_label")) \(Int(vm.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricBubble(title: languageManager.text("metric_rate"), value: "\(Int(vm.compressionsPerMinute)) CPM", symbol: "metronome.fill", target: "100–120")
                MetricBubble(title: languageManager.text("metric_depth"), value: String(format: "%.1f cm", vm.estimatedDepthCm), symbol: "arrow.down.to.line", target: "5–6 cm")
                MetricBubble(title: languageManager.text("metric_elbow"), value: "\(Int(vm.elbowAngle))°", symbol: "angle", target: ">165°")
                MetricBubble(title: languageManager.text("metric_hands"), value: languageManager.handPlacement(HandPlacement(rawValue: vm.handPlacement) ?? .unknown), symbol: "hand.raised.fill", target: languageManager.text("placement_centered"))
                MetricBubble(title: languageManager.text("metric_recoil"), value: languageManager.recoilQuality(vm.recoilQuality), symbol: "arrow.up.and.down", target: languageManager.text("recoil_full"))
                MetricBubble(title: languageManager.text("metric_motion"), value: String(format: "%.3f", vm.motionAmplitude), symbol: "waveform.path", target: languageManager.text("metric_steady"))
            }
            .frame(maxWidth: .infinity)
        }
    }

    //  Legal disclaimer: training tool, not a medical device 
    private var disclaimerCard: some View {
        GlassCard {
            Text(CPRGuidelines.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

//  Small reusable UI components used on the coach screen 

struct StatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct MiniInfoBubble: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

//  Animated rhythm bar synced to compression rate 
struct RhythmBar: View {
    @EnvironmentObject private var languageManager: LanguageManager
    let phase: Double
    let cpm: Double

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(cpm > 0 ? Color.red : Color.gray)
                        .frame(width: max(8, geo.size.width * (0.3 + phase * 0.7)))
                }
            }
            .frame(height: 8)

            Text(cpm > 0 ? "\(languageManager.text("metric_rate")) \(Int(cpm)) CPM" : languageManager.text("metric_rate"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
