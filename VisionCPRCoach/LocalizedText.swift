import SwiftUI

/// Observes LanguageManager so UI updates when language changes.
struct Loc: View {
    let key: String
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        Text(languageManager.text(key))
    }
}

struct LocLabel: View {
    let key: String
    let systemImage: String
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        Label(languageManager.text(key), systemImage: systemImage)
    }
}
