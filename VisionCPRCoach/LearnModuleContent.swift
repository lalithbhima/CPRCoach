import Foundation
import SwiftUI

struct LearnModuleContent: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let overview: String
    let bullets: [String]
    let steps: [String]
    let icon: String
    let color: Color

    private static let specs: [(id: String, icon: String, colorName: String, bulletCount: Int, stepCount: Int)] = [
        ("assess", "eye.fill", "orange", 10, 7),
        ("compress", "hands.clap.fill", "red", 12, 8),
        ("quality", "chart.bar.fill", "blue", 11, 8),
        ("aed", "bolt.heart.fill", "green", 12, 8)
    ]

    @MainActor
    static func modules(for languageManager: LanguageManager) -> [LearnModuleContent] {
        specs.map { spec in
            let prefix = "learn_\(spec.id)"
            return LearnModuleContent(
                id: spec.id,
                title: languageManager.text("\(prefix)_title"),
                summary: languageManager.text("\(prefix)_summary"),
                overview: languageManager.text("\(prefix)_overview"),
                bullets: (0..<spec.bulletCount).map { languageManager.text("\(prefix)_bullet_\($0)") },
                steps: (0..<spec.stepCount).map { languageManager.text("\(prefix)_step_\($0)") },
                icon: spec.icon,
                color: color(named: spec.colorName)
            )
        }
    }

    private static func color(named: String) -> Color {
        switch named {
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        default: return .red
        }
    }
}
