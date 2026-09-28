import SwiftUI
import Charts

private struct ExportSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct CPRProgressView: View {
    @ObservedObject var store = CPRProgressStore.shared
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var exportPayload: ExportSharePayload?
    @State private var exportErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                overviewCard
                if let latest = store.latestSession {
                    latestSessionCard(latest)
                }
                if store.sessions.count >= 2 {
                    improvementChart
                }
                calibrationCard
                sessionHistory
            }
            .padding(16)
        }
        .background(BubbleBackground().ignoresSafeArea())
        .navigationTitle(languageManager.text("progress_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportSessions()
                } label: {
                    Label(languageManager.text("progress_export_data"), systemImage: "square.and.arrow.up")
                }
                .disabled(store.sessions.isEmpty)
            }
        }
        .sheet(item: $exportPayload) { payload in
            CPRShareSheet(url: payload.url)
                .ignoresSafeArea()
        }
        .alert(
            languageManager.text("progress_export_failed"),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func exportSessions() {
        do {
            let url = try CPRSessionExportService.shared.makeTrainingExportFile(progressStore: store)
            exportPayload = ExportSharePayload(url: url)
        } catch CPRSessionExportService.ExportError.noSessions {
            exportErrorMessage = languageManager.text("progress_export_empty")
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private var overviewCard: some View {
        FloatingBubbleCard(accent: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageManager.text("progress_score_title"))
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(store.aggregateScore))%")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(languageManager.text("progress_training_score"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let delta = store.improvementSincePrevious() {
                    let sign = delta >= 0 ? "+" : ""
                    Text(languageManager.textFormat("progress_improved", "\(sign)\(Int(delta))"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? .green : .orange)
                } else if store.sessions.isEmpty {
                    Text(languageManager.text("progress_empty_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let latest = store.latestSession {
                    let percentile = CPRSessionScoring.peerPercentile(for: latest.overallScore)
                    Text(languageManager.textFormat("progress_peer_rank", "\(percentile)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func latestSessionCard(_ session: CPRPracticeSession) -> some View {
        FloatingBubbleCard(accent: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                Text(languageManager.text("progress_latest_session"))
                    .font(.headline)

                Text("\(session.formattedStart) → \(session.formattedEnd)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(session.formattedDuration)
                    .font(.title3.bold())

                metricRow(languageManager.text("metric_rate"), "\(Int(session.averageCPM)) CPM")
                metricRow(languageManager.text("metric_depth"), String(format: "%.1f cm", session.averageDepthCm))
                metricRow(languageManager.text("progress_hands_centered"), "\(Int(session.handsOnTargetPercentage * 100))%")
                metricRow(languageManager.text("progress_elbows_locked"), "\(Int(session.elbowLockAccuracy * 100))%")
                metricRow(languageManager.text("metric_recoil"), "\(Int(session.recoilAccuracy * 100))%")

                Divider()

                Text(languageManager.text("progress_main_fix"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(languageManager.localizedFeedback(session.mainMistakeKey))
                    .font(.subheadline.weight(.semibold))

                NavigationLink {
                    CPRSessionDetailView(session: session)
                } label: {
                    Label(languageManager.text("progress_view_details"), systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryBubbleButtonStyle())
            }
        }
    }

    private var improvementChart: some View {
        FloatingBubbleCard(accent: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageManager.text("progress_score_over_time"))
                    .font(.headline)

                Chart(Array(store.sessions.prefix(12).reversed().enumerated()), id: \.element.id) { index, session in
                    LineMark(
                        x: .value("Session", index + 1),
                        y: .value("Score", session.overallScore)
                    )
                    .foregroundStyle(.red)
                    PointMark(
                        x: .value("Session", index + 1),
                        y: .value("Score", session.overallScore)
                    )
                    .foregroundStyle(.red)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
            }
        }
    }

    private var calibrationCard: some View {
        let profile = AppConfig.loadCalibration()
        return FloatingBubbleCard(accent: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Text(languageManager.text("progress_calibration_profile"))
                    .font(.headline)

                LabeledContent(languageManager.text("settings_calibration_toggle"), value: profile.isCalibrated ? languageManager.text("progress_yes") : languageManager.text("progress_no"))
                if profile.isCalibrated {
                    LabeledContent(languageManager.text("settings_baseline_depth"), value: String(format: "%.1f cm", profile.baselineDepthCm))
                    LabeledContent(languageManager.text("settings_baseline_amp"), value: String(format: "%.3f", profile.baselineAmplitude))
                }
                if let last = store.calibrationRecords.first {
                    LabeledContent(languageManager.text("progress_last_calibrated"), value: last.formattedDate)
                }

                NavigationLink {
                    CalibrationHistoryView()
                } label: {
                    Label(languageManager.text("progress_view_calibration_history"), systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryBubbleButtonStyle())
            }
        }
    }

    private var sessionHistory: some View {
        FloatingBubbleCard(accent: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageManager.text("progress_saved_sessions"))
                    .font(.headline)

                if store.sessions.isEmpty {
                    Text(languageManager.text("progress_no_sessions"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions) { session in
                        NavigationLink {
                            CPRSessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(.plain)

                        if session.id != store.sessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: CPRPracticeSession) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.formattedStart)
                    .font(.subheadline.weight(.semibold))
                Text(session.formattedEnd)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(languageManager.text("progress_score_label")) \(Int(session.overallScore))% · \(Int(session.averageCPM)) CPM · \(String(format: "%.1f", session.averageDepthCm)) cm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(languageManager.localizedFeedback(session.mainMistakeKey))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
