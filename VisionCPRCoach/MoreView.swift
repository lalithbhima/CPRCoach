import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        NavigationStack {
            ZStack {
                BubbleBackground().ignoresSafeArea()

                List {
                    Section {
                        NavigationLink {
                            HospitalsView()
                        } label: {
                            moreRow(
                                title: languageManager.text("tab_hospitals"),
                                subtitle: languageManager.text("hospitals_footer"),
                                icon: "map.fill",
                                tint: .blue
                            )
                        }

                        NavigationLink {
                            AEDsView()
                        } label: {
                            moreRow(
                                title: languageManager.text("tab_aeds"),
                                subtitle: languageManager.text("aeds_more_subtitle"),
                                icon: "bolt.heart.fill",
                                tint: .green
                            )
                        }

                        NavigationLink {
                            CPRProgressView()
                        } label: {
                            moreRow(
                                title: languageManager.text("tab_progress"),
                                subtitle: languageManager.text("progress_more_subtitle"),
                                icon: "chart.line.uptrend.xyaxis",
                                tint: .red
                            )
                        }

                        NavigationLink {
                            CalibrationHistoryView()
                        } label: {
                            moreRow(
                                title: languageManager.text("tab_calibration"),
                                subtitle: languageManager.text("calibration_more_subtitle"),
                                icon: "scope",
                                tint: .orange
                            )
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            moreRow(
                                title: languageManager.text("settings_title"),
                                subtitle: languageManager.text("settings_more_subtitle"),
                                icon: "gearshape.fill",
                                tint: .gray
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(languageManager.text("tab_more"))
        }
    }

    private func moreRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
