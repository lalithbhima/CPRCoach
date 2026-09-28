import SwiftUI

// MARK: - Bubble design system (novel glass/bubble UI)

struct BubbleBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.95, blue: 0.96),
                    Color(red: 0.94, green: 0.97, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            orb(.red, size: 240, blur: 64, base: CGSize(width: -120, height: -200), shift: CGSize(width: 18, height: 26))
            orb(.blue, size: 190, blur: 52, base: CGSize(width: 140, height: 100), shift: CGSize(width: -24, height: -18))
            orb(.pink, size: 150, blur: 44, base: CGSize(width: 80, height: -80), shift: CGSize(width: 16, height: 30))
            orb(.purple, size: 130, blur: 46, base: CGSize(width: -90, height: 220), shift: CGSize(width: 22, height: -20))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func orb(_ color: Color, size: CGFloat, blur: CGFloat, base: CGSize, shift: CGSize) -> some View {
        Circle()
            .fill(color.opacity(0.08))
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(
                x: base.width + (drift ? shift.width : 0),
                y: base.height + (drift ? shift.height : 0)
            )
    }
}

struct FloatingBubbleCard<Content: View>: View {
    var accent: Color = .red
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: accent.opacity(0.12), radius: 20, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.9), accent.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}

struct VoiceOrb: View {
    /// Voice AI session is on — show idle breathing pulse.
    var isOn: Bool
    /// Listening, speaking, or processing — stronger outward ripples.
    var isLive: Bool
    let label: String
    @State private var coreExpanded = false

    init(isActive: Bool, label: String) {
        isOn = isActive
        isLive = isActive
        self.label = label
    }

    init(isOn: Bool, isLive: Bool = false, label: String) {
        self.isOn = isOn
        self.isLive = isLive
        self.label = label
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if isOn {
                    ForEach(0..<3, id: \.self) { index in
                        VoicePulseRing(
                            delay: Double(index) * 0.55,
                            isLive: isLive
                        )
                    }
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(isOn ? 0.45 : 0.2),
                                Color.red.opacity(0.02)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 40
                        )
                    )
                    .frame(width: isOn ? 76 : 64, height: isOn ? 76 : 64)
                    .scaleEffect(isOn && coreExpanded ? (isLive ? 1.12 : 1.06) : 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color(red: 0.85, green: 0.12, blue: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: .red.opacity(isOn ? 0.45 : 0.2), radius: isOn ? 14 : 6, y: 4)
                    .scaleEffect(isOn && coreExpanded ? (isLive ? 1.05 : 1.02) : 1)
                    .overlay {
                        Image(systemName: iconName)
                            .foregroundStyle(.white)
                            .font(.title3.weight(.semibold))
                            .symbolEffect(.variableColor.iterative, isActive: isLive)
                    }
            }
            .frame(width: 88, height: 88)

            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { startCorePulse() }
        .onChange(of: isOn) { _, _ in startCorePulse() }
        .onChange(of: isLive) { _, _ in startCorePulse() }
    }

    private func startCorePulse() {
        coreExpanded = false
        guard isOn else { return }
        withAnimation(
            .easeInOut(duration: isLive ? 0.9 : 1.4)
            .repeatForever(autoreverses: true)
        ) {
            coreExpanded = true
        }
    }

    private var iconName: String {
        if !isOn { return "mic.fill" }
        return isLive ? "waveform" : "mic.circle.fill"
    }
}

/// Staggered ring that expands outward then eases back inward.
private struct VoicePulseRing: View {
    let delay: Double
    let isLive: Bool

    @State private var expanded = false

    private var duration: Double { isLive ? 1.35 : 2.1 }

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.red.opacity(0.55), Color.red.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: isLive ? 2.5 : 1.5
            )
            .frame(width: 52, height: 52)
            .scaleEffect(expanded ? (isLive ? 2.05 : 1.75) : 0.82)
            .opacity(expanded ? 0 : (isLive ? 0.55 : 0.38))
            .onAppear { startAnimation() }
            .onChange(of: isLive) { _, _ in startAnimation() }
    }

    private func startAnimation() {
        expanded = false
        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            expanded = true
        }
    }
}

struct PillBubble: View {
    let text: String
    var color: Color = .red

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct HeroHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: .red.opacity(0.3), radius: 12, y: 6)

                Image(systemName: icon)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
