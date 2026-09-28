import SwiftUI
import Charts

struct CPRSessionDetailView: View {
    let session: CPRPracticeSession

    @ObservedObject private var store = CPRProgressStore.shared
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var aiSummary = ""
    @State private var isLoadingAI = false

    private var liveSession: CPRPracticeSession {
        store.sessions.first(where: { $0.id == session.id }) ?? session
    }

    private var chartFrames: [CPRFrameMetric] {
        downsample(liveSession.frames, maxPoints: 120)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                scoreHeader
                timelineSection
                highlightsSection
                correctionsSection
                aiSummarySection
                calibrationSection
            }
            .padding(16)
        }
        .background(BubbleBackground().ignoresSafeArea())
        .navigationTitle(languageManager.text("progress_session_detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAISummaryIfNeeded()
        }
    }

    private var scoreHeader: some View {
        FloatingBubbleCard(accent: .red) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(liveSession.overallScore))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("\(liveSession.formattedStart) — \(liveSession.formattedEnd)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(liveSession.formattedDuration)
                    .font(.title3.bold())
                Text(languageManager.textFormat("progress_peer_rank", "\(CPRSessionScoring.peerPercentile(for: liveSession.overallScore))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timelineSection: some View {
        FloatingBubbleCard(accent: .blue) {
            VStack(alignment: .leading, spacing: 16) {
                Text(languageManager.text("progress_timeline"))
                    .font(.headline)

                chartBlock(title: languageManager.text("metric_rate"), unit: "CPM", color: .red) {
                    Chart(chartFrames) { frame in
                        LineMark(x: .value("t", frame.timestamp), y: .value("CPM", frame.cpm))
                    }
                    .chartYScale(domain: 0...140)
                }

                chartBlock(title: languageManager.text("metric_depth"), unit: "cm", color: .blue) {
                    Chart(chartFrames) { frame in
                        LineMark(x: .value("t", frame.timestamp), y: .value("Depth", frame.depthCm))
                    }
                    .chartYScale(domain: 0...8)
                }

                chartBlock(title: languageManager.text("progress_hand_accuracy"), unit: "%", color: .green) {
                    Chart(chartFrames) { frame in
                        LineMark(x: .value("t", frame.timestamp), y: .value("Hands", frame.handPlacementScore * 100))
                    }
                    .chartYScale(domain: 0...100)
                }

                chartBlock(title: languageManager.text("metric_elbow"), unit: "°", color: .orange) {
                    Chart(chartFrames) { frame in
                        LineMark(
                            x: .value("t", frame.timestamp),
                            y: .value("Elbow", clampedElbowAngle(frame.elbowAngle))
                        )
                    }
                    .chartYScale(domain: 120...180)
                }
            }
        }
    }

    private var highlightsSection: some View {
        let best = liveSession.frames.max(by: { $0.pressureScore < $1.pressureScore })
        let worst = liveSession.frames.min(by: { $0.pressureScore < $1.pressureScore })

        return FloatingBubbleCard(accent: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                Text(languageManager.text("progress_highlights"))
                    .font(.headline)

                if let best {
                    highlightRow(
                        title: languageManager.text("progress_best_moment"),
                        frame: best,
                        tint: .green
                    )
                }
                if let worst {
                    highlightRow(
                        title: languageManager.text("progress_worst_moment"),
                        frame: worst,
                        tint: .orange
                    )
                }
            }
        }
    }

    private var correctionsSection: some View {
        FloatingBubbleCard(accent: .orange) {
            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("progress_main_corrections"))
                    .font(.headline)
                Text(languageManager.localizedFeedback(liveSession.mainMistakeKey))
                    .font(.subheadline.weight(.semibold))
                Text(languageManager.text(liveSession.improvementSuggestionKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aiSummarySection: some View {
        FloatingBubbleCard(accent: .red) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(languageManager.text("progress_ai_summary"))
                        .font(.headline)
                    Spacer()
                    if isLoadingAI {
                        ProgressView().controlSize(.small)
                    }
                }

                Text(aiSummary.isEmpty ? languageManager.text("progress_ai_loading") : aiSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calibrationSection: some View {
        FloatingBubbleCard(accent: .gray) {
            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("progress_calibration_used"))
                    .font(.headline)
                LabeledContent(languageManager.text("progress_calibration_active"), value: liveSession.calibrationWasUsed ? languageManager.text("progress_yes") : languageManager.text("progress_no"))
                LabeledContent(languageManager.text("settings_baseline_depth"), value: String(format: "%.1f cm", liveSession.calibrationBaselineDepth))
                LabeledContent(languageManager.text("settings_baseline_amp"), value: String(format: "%.3f", liveSession.calibrationBaselineAmplitude))
            }
        }
    }

    @ViewBuilder
    private func chartBlock<Content: View>(title: String, unit: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(unit))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(height: 120)
                .padding(.vertical, 4)
                .clipped()
                .foregroundStyle(color)
        }
    }

    /// Keeps elbow plot inside 120–180° so pose glitches don't spike off-chart.
    private func clampedElbowAngle(_ angle: Double) -> Double {
        min(180, max(120, angle))
    }

    private func highlightRow(title: String, frame: CPRFrameMetric, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text("t=\(String(format: "%.1f", frame.timestamp))s · \(Int(frame.cpm)) CPM · \(String(format: "%.1f", frame.depthCm)) cm · \(Int(frame.elbowAngle))°")
                .font(.footnote)
        }
    }

    private func loadAISummaryIfNeeded() async {
        if let cached = liveSession.aiSummary, !cached.isEmpty {
            aiSummary = cached
            return
        }

        isLoadingAI = true
        let prior = store.sessions.filter { $0.id != session.id }
        let summary = await CPRSessionAnalysisService.shared.generateAISummary(
            session: liveSession,
            priorSessions: prior
        )
        aiSummary = summary
        store.updateAISummary(sessionID: session.id, summary: summary)
        isLoadingAI = false
    }

    private func downsample(_ frames: [CPRFrameMetric], maxPoints: Int) -> [CPRFrameMetric] {
        guard frames.count > maxPoints else { return frames }
        let step = max(1, frames.count / maxPoints)
        return frames.enumerated().compactMap { index, frame in
            index % step == 0 ? frame : nil
        }
    }
}
