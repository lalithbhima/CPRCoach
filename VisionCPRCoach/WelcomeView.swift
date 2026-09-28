import SwiftUI

/// Scattered red / peach / pink washes — welcome screen only.
private struct WelcomeBackground: View {
    @State private var drift = false

    private let softRed = Color(red: 0.92, green: 0.28, blue: 0.34)
    private let softPeach = Color(red: 1.0, green: 0.78, blue: 0.66)
    private let softPink = Color(red: 1.0, green: 0.62, blue: 0.74)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.86, blue: 0.88),
                    Color(red: 1.0, green: 0.90, blue: 0.86),
                    Color(red: 0.96, green: 0.82, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            wash(softRed, size: 360, blur: 50, opacity: 0.42, base: CGSize(width: -140, height: -240), shift: CGSize(width: 24, height: 32))
            wash(softPeach, size: 330, blur: 46, opacity: 0.38, base: CGSize(width: 160, height: -80), shift: CGSize(width: -30, height: 26))
            wash(softPink, size: 300, blur: 44, opacity: 0.36, base: CGSize(width: 30, height: 200), shift: CGSize(width: 20, height: -28))
            wash(softRed, size: 280, blur: 42, opacity: 0.34, base: CGSize(width: -90, height: 140), shift: CGSize(width: -22, height: 20))
            wash(softPeach, size: 260, blur: 40, opacity: 0.34, base: CGSize(width: 120, height: 280), shift: CGSize(width: 26, height: -24))
            wash(softPink, size: 290, blur: 48, opacity: 0.32, base: CGSize(width: -170, height: 60), shift: CGSize(width: 18, height: 22))
            wash(softRed, size: 240, blur: 38, opacity: 0.30, base: CGSize(width: 100, height: -200), shift: CGSize(width: -16, height: 18))
            wash(softPeach, size: 220, blur: 42, opacity: 0.28, base: CGSize(width: -200, height: -120), shift: CGSize(width: 20, height: 16))
            wash(softPink, size: 250, blur: 40, opacity: 0.28, base: CGSize(width: 200, height: 160), shift: CGSize(width: -18, height: -20))
            wash(softRed, size: 200, blur: 36, opacity: 0.26, base: CGSize(width: 0, height: 320), shift: CGSize(width: 14, height: -16))
            wash(Color.white, size: 220, blur: 50, opacity: 0.12, base: CGSize(width: 0, height: 0), shift: CGSize(width: 12, height: -14))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func wash(
        _ color: Color,
        size: CGFloat,
        blur: CGFloat,
        opacity: Double,
        base: CGSize,
        shift: CGSize
    ) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(
                x: base.width + (drift ? shift.width : 0),
                y: base.height + (drift ? shift.height : 0)
            )
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Binding var isComplete: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                WelcomeBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    PulsingWelcomeLogo()
                        .padding(.horizontal, 48)

                    Spacer()
                        .frame(height: 52)

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isComplete = true
                        }
                    } label: {
                        Text(languageManager.text("welcome_button"))
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryBubbleButtonStyle())
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
        .id(languageManager.localeRevision)
    }
}
