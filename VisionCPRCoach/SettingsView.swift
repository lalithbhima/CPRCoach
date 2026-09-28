import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var calibration = AppConfig.loadCalibration()
    @State private var savedMessage = ""

    var body: some View {
        Form {
                Section(languageManager.text("settings_language_section")) {
                    Picker(languageManager.text("settings_language_picker"), selection: Binding(
                        get: { languageManager.current },
                        set: { languageManager.setLanguage($0) }
                    )) {
                        ForEach(languageManager.languages) { lang in
                            Text(lang.pickerLabel).tag(lang)
                        }
                    }
                }

                Section(languageManager.text("settings_calibration")) {
                    Toggle(languageManager.text("settings_calibration_toggle"), isOn: Binding(
                        get: { calibration.isCalibrated },
                        set: { calibration.isCalibrated = $0 }
                    ))

                    if calibration.isCalibrated {
                        LabeledContent(languageManager.text("settings_baseline_amp"), value: String(format: "%.3f", calibration.baselineAmplitude))
                        LabeledContent(languageManager.text("settings_baseline_depth"), value: String(format: "%.1f cm", calibration.baselineDepthCm))
                    }

                    Text(languageManager.text("settings_calibration_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(languageManager.text("settings_about")) {
                    LabeledContent(languageManager.text("settings_version"), value: "1.0")
                    LabeledContent(languageManager.text("settings_architecture"), value: languageManager.text("settings_architecture_value"))
                    LabeledContent(languageManager.text("settings_target_rate"), value: "100–120 CPM")
                    LabeledContent(languageManager.text("settings_target_depth"), value: "5–6 cm")
                }

                Section(languageManager.text("settings_training_data")) {
                    Text(languageManager.text("settings_training_data_body"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        DataSourcesView()
                    } label: {
                        Label(languageManager.text("settings_data_sources"), systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section {
                    Button(languageManager.text("settings_save")) {
                        AppConfig.saveCalibration(calibration)
                        savedMessage = languageManager.text("settings_saved")
                    }
                }

                if !savedMessage.isEmpty {
                    Section {
                        Text(savedMessage).foregroundStyle(.green)
                    }
                }

                Section {
                    Text(CPRGuidelines.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        .navigationTitle(languageManager.text("settings_title"))
        .scrollContentBackground(.hidden)
        .background(BubbleBackground().ignoresSafeArea())
    }
}
