import SwiftUI

/// Slow expand-then-shrink pulse for the welcome logo.
enum HeartbeatPulse {
    private static let cycleSeconds: Double = 1.35
    private static let expandSeconds: Double = 0.42
    private static let shrinkSeconds: Double = 0.42
    private static let peakScale: CGFloat = 1.08

    static func scale(at time: TimeInterval) -> CGFloat {
        let t = time.truncatingRemainder(dividingBy: cycleSeconds)
        if t < expandSeconds {
            return 1.0 + (peakScale - 1.0) * easeInOut(t / expandSeconds)
        }
        if t < expandSeconds + shrinkSeconds {
            let x = (t - expandSeconds) / shrinkSeconds
            return peakScale - (peakScale - 1.0) * easeInOut(x)
        }
        return 1.0
    }

    static func glowOpacity(at time: TimeInterval) -> Double {
        let t = time.truncatingRemainder(dividingBy: cycleSeconds)
        if t < expandSeconds {
            return 0.2 + 0.35 * easeInOut(t / expandSeconds)
        }
        if t < expandSeconds + shrinkSeconds {
            let x = (t - expandSeconds) / shrinkSeconds
            return 0.55 - 0.35 * easeInOut(x)
        }
        return 0.15
    }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}

struct PulsingWelcomeLogo: View {
    private let bubbleCorner: CGFloat = 22
    private let bubblePadding: CGFloat = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let scale = HeartbeatPulse.scale(at: t)
            let glow = HeartbeatPulse.glowOpacity(at: t)

            ZStack {
                RoundedRectangle(cornerRadius: bubbleCorner + bubblePadding, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .red.opacity(glow * 0.35), radius: 22, y: 10)
                    .shadow(color: .white.opacity(glow * 0.25), radius: 8, y: -3)

                RoundedRectangle(cornerRadius: bubbleCorner + bubblePadding, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.92),
                                .white.opacity(0.45),
                                Color.red.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )

                RoundedRectangle(cornerRadius: bubbleCorner + bubblePadding, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 3)
                    .blur(radius: 2)
                    .padding(-1)

                Image("CPRCoachLogo")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
                    .padding(bubblePadding)
            }
            .scaleEffect(scale)
        }
        .frame(maxWidth: 276, maxHeight: 276)
        .accessibilityLabel("CPR Coach")
    }
}
