import SwiftUI

/// Training data sources — detailed guide in Settings (not shown on coaching screens).
struct DataSourcesView: View {
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeroHeader(
                    title: languageManager.text("settings_data_sources"),
                    subtitle: languageManager.text("settings_training_data_body"),
                    icon: "doc.text.magnifyingglass"
                )

                sourceCard(
                    phase: "Voice & Chat Coaching",
                    color: .purple,
                    sources: [
                        ("National & international CPR curricula", "Evidence-based resuscitation content from major BLS programs worldwide — integrated into on-device knowledge retrieval."),
                        ("Peer-reviewed literature", "PubMed and scholarly sources on CPR technique, cardiac arrest, and emergency cardiovascular care."),
                        ("On-device knowledge base", "Bundled cpr_knowledge.json with searchable chunks used by the emergency voice assistant and ChatCPR."),
                        ("Prompt engineering", "This app does not fine-tune a custom LLM. It uses retrieval + careful prompts for grounded, safe outputs.")
                    ],
                    action: ("Expand knowledge", "Add entries to Resources/cpr_knowledge.json from accredited CPR training materials.")
                )

                sourceCard(
                    phase: "Computer Vision",
                    color: .red,
                    sources: [
                        ("CPR demonstration videos", "Professional demonstrations for variance in angles, lighting, and body types."),
                        ("Custom recordings", "Self-record on a CPR manikin with consistent lighting and camera angle."),
                        ("Roboflow (optional)", "Label keypoints and hand boxes; augment for skin tone and lighting."),
                        ("This app (now)", "On-device pose tracking + rate/depth estimation — no custom dataset required.")
                    ],
                    action: ("Optional upgrade", "Record clips → label on roboflow.com → export Core ML for custom pose models.")
                )

                sourceCard(
                    phase: "Validation",
                    color: .blue,
                    sources: [
                        ("CPR manikin + force sensor", "Ground-truth compression depth in centimeters."),
                        ("Digital metronome", "Ground-truth compression rate (CPM)."),
                        ("In-app calibration", "Personalizes depth estimates without a force sensor.")
                    ],
                    action: ("Calibrate", "Coach tab → 30 seconds of good compressions → tap Calibrate.")
                )

                FloatingBubbleCard(accent: .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended order")
                            .font(.headline)
                        Text("1. Use the app with built-in vision and knowledge retrieval.\n2. Expand cpr_knowledge.json with additional accredited training content.\n3. Optional: custom vision dataset for specialized pose models.\n4. Optional: manikin + sensor for clinical validation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(BubbleBackground().ignoresSafeArea())
        .navigationTitle(languageManager.text("settings_data_sources"))
    }

    @ViewBuilder
    private func sourceCard(
        phase: String,
        color: Color,
        sources: [(String, String)],
        action: (String, String)
    ) -> some View {
        FloatingBubbleCard(accent: color) {
            VStack(alignment: .leading, spacing: 12) {
                PillBubble(text: phase, color: color)

                ForEach(sources, id: \.0) { title, detail in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.0)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                    Text(action.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
