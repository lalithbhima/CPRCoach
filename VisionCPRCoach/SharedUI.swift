import SwiftUI
import UIKit

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

struct MetricBubble: View {
    let title: String
    let value: String
    let symbol: String
    var target: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                if !target.isEmpty {
                    Text("Target: \(target)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.65), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

struct PrimaryBubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.red.opacity(configuration.isPressed ? 0.75 : 1.0)))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SecondaryBubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.55 : 0.78)))
            .foregroundStyle(.red)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.7), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SoftPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.tertiarySystemFill)))
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}

struct PoseOverlayView: View {
    let joints: BodyJoints?

    var body: some View {
        GeometryReader { geo in
            if let joints {
                let points = scaledPoints(for: joints, in: geo.size)
                ZStack {
                    line(points.leftShoulder, points.leftElbow)
                    line(points.leftElbow, points.leftWrist)
                    line(points.rightShoulder, points.rightElbow)
                    line(points.rightElbow, points.rightWrist)
                    line(points.leftShoulder, points.rightShoulder)
                    jointCircle(points.leftWrist, color: .red)
                    jointCircle(points.rightWrist, color: .red)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func scaledPoints(for joints: BodyJoints, in size: CGSize) -> OverlayPoints {
        func convert(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: (1.0 - p.y) * size.height)
        }
        return OverlayPoints(
            leftShoulder: convert(joints.leftShoulder),
            rightShoulder: convert(joints.rightShoulder),
            leftElbow: convert(joints.leftElbow),
            rightElbow: convert(joints.rightElbow),
            leftWrist: convert(joints.leftWrist),
            rightWrist: convert(joints.rightWrist)
        )
    }

    private func jointCircle(_ point: CGPoint, color: Color) -> some View {
        Circle().fill(color).frame(width: 10, height: 10).position(point)
    }

    private func line(_ p1: CGPoint, _ p2: CGPoint) -> some View {
        Path { path in
            path.move(to: p1)
            path.addLine(to: p2)
        }
        .stroke(Color.white, lineWidth: 3)
    }

    private struct OverlayPoints {
        let leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist: CGPoint
    }
}

struct CPRShareSheet: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> ShareActivityHostController {
        ShareActivityHostController(url: url) {
            dismiss()
        }
    }

    func updateUIViewController(_ uiViewController: ShareActivityHostController, context: Context) {}
}

final class ShareActivityHostController: UIViewController {
    private let url: URL
    private let onComplete: () -> Void
    private var didPresent = false

    init(url: URL, onComplete: @escaping () -> Void) {
        self.url = url
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 0,
            height: 0
        )
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.onComplete()
        }
        present(activity, animated: true)
    }
}
