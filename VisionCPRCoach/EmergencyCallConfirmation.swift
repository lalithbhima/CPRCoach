import SwiftUI

extension View {
    func emergencyCallConfirmation(
        isPresented: Binding<Bool>,
        number: String,
        languageManager: LanguageManager
    ) -> some View {
        alert(
            languageManager.textFormat("call_emergency_confirm_title", number),
            isPresented: isPresented
        ) {
            Button(languageManager.text("confirm_no"), role: .cancel) {}
            Button(languageManager.text("confirm_yes"), role: .destructive) {
                EmergencyNumberService.dial(number)
            }
        } message: {
            Text(languageManager.textFormat("call_emergency_confirm_message", number))
        }
    }
}
