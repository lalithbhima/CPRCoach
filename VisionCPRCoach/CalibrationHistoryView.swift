import SwiftUI

struct CalibrationHistoryView: View {
    @ObservedObject private var store = CPRProgressStore.shared
    @EnvironmentObject private var languageManager: LanguageManager

    private var profile: CalibrationProfile { AppConfig.loadCalibration() }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FloatingBubbleCard(accent: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(languageManager.text("progress_calibration_profile"))
                            .font(.headline)
                        LabeledContent(languageManager.text("settings_calibration_toggle"), value: profile.isCalibrated ? languageManager.text("progress_yes") : languageManager.text("progress_no"))
                        if profile.isCalibrated {
                            LabeledContent(languageManager.text("settings_baseline_depth"), value: String(format: "%.1f cm", profile.baselineDepthCm))
                            LabeledContent(languageManager.text("settings_baseline_amp"), value: String(format: "%.3f", profile.baselineAmplitude))
                        }
                        Text(languageManager.text("settings_calibration_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                FloatingBubbleCard(accent: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(languageManager.text("progress_calibration_history"))
                            .font(.headline)

                        if store.calibrationRecords.isEmpty {
                            Text(languageManager.text("progress_no_calibrations"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.calibrationRecords) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.formattedDate)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(languageManager.text("settings_baseline_depth")) \(String(format: "%.1f", record.baselineDepthCm)) cm · \(languageManager.text("settings_baseline_amp")) \(String(format: "%.3f", record.baselineAmplitude))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(languageManager.text("metric_rate")) \(Int(record.cpmAtCalibration)) CPM · \(languageManager.text("metric_depth")) \(String(format: "%.1f", record.depthCmAtCalibration)) cm · \(languageManager.text("metric_elbow")) \(Int(record.elbowAngleAtCalibration))°")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)

                                if record.id != store.calibrationRecords.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(BubbleBackground().ignoresSafeArea())
        .navigationTitle(languageManager.text("tab_calibration"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
