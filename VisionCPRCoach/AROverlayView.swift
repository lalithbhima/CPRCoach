import SwiftUI

struct AROverlayView: View {
    let joints: BodyJoints?
    let handPlacement: String
    let rhythmPhase: Double
    let cpm: Double
    let depthQuality: DepthEstimate

    var body: some View {
        GeometryReader { geo in
            if let joints {
                let points = scaledPoints(for: joints, in: geo.size)
                let chestCenter = chestTarget(in: points)

                ZStack {
                    skeletonLines(points)
                    handPlacementTarget(at: chestCenter, in: geo.size)
                    compressionArrow(at: chestCenter, in: geo.size)
                    depthIndicator(at: chestCenter, in: geo.size)
                }
            } else {
                placementGuide(in: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func placementGuide(in size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: size.width * 0.28, height: size.height * 0.18)
                .position(x: size.width * 0.5, y: size.height * 0.55)

            Text(LanguageManager.shared.text("overlay_align_hands"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .position(x: size.width * 0.5, y: size.height * 0.42)
        }
    }

    private func handPlacementTarget(at center: CGPoint, in size: CGSize) -> some View {
        let isCentered = handPlacement == HandPlacement.centered.rawValue
        let color: Color = isCentered ? .green : .orange

        return ZStack {
            Circle()
                .stroke(color.opacity(0.9), lineWidth: 3)
                .frame(width: 56, height: 56)
                .position(center)

            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 44, height: 44)
                .position(center)

            Text("✋")
                .font(.title2)
                .position(center)
        }
    }

    private func compressionArrow(at center: CGPoint, in size: CGSize) -> some View {
        let depthOffset = depthQuality == .tooShallow ? 18.0 : 28.0
        let animatedY = center.y + sin(rhythmPhase * .pi * 2) * 6

        return Path { path in
            path.move(to: CGPoint(x: center.x, y: animatedY - depthOffset))
            path.addLine(to: CGPoint(x: center.x, y: animatedY + depthOffset * 0.3))
        }
        .stroke(
            depthQuality == .adequate ? Color.green : Color.red,
            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 4])
        )
        .overlay {
            Image(systemName: "arrow.down")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .position(x: center.x, y: animatedY - depthOffset - 10)
        }
    }

    private func depthIndicator(at center: CGPoint, in size: CGSize) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(index: i))
                    .frame(width: 8, height: CGFloat(12 + i * 4))
            }
        }
        .position(x: center.x + 50, y: center.y)
    }

    private func barColor(index: Int) -> Color {
        switch depthQuality {
        case .adequate: return .green.opacity(Double(index + 1) / 5.0)
        case .tooShallow: return index < 2 ? .orange : .white.opacity(0.2)
        case .tooDeep: return .red.opacity(Double(index + 1) / 5.0)
        case .unknown: return .white.opacity(0.3)
        }
    }

    private func skeletonLines(_ points: OverlayPoints) -> some View {
        ZStack {
            line(points.leftShoulder, points.leftElbow, color: .white.opacity(0.8))
            line(points.leftElbow, points.leftWrist, color: .white.opacity(0.8))
            line(points.rightShoulder, points.rightElbow, color: .white.opacity(0.8))
            line(points.rightElbow, points.rightWrist, color: .white.opacity(0.8))
            line(points.leftShoulder, points.rightShoulder, color: .cyan.opacity(0.7))

            jointCircle(points.leftWrist, color: .red)
            jointCircle(points.rightWrist, color: .red)
        }
    }

    private func chestTarget(in points: OverlayPoints) -> CGPoint {
        let shoulderMid = midpoint(points.leftShoulder, points.rightShoulder)
        let wristMid = midpoint(points.leftWrist, points.rightWrist)
        return CGPoint(
            x: (shoulderMid.x + wristMid.x) / 2,
            y: shoulderMid.y + (wristMid.y - shoulderMid.y) * 0.15
        )
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

    private func midpoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }

    private func jointCircle(_ point: CGPoint, color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12).position(point)
    }

    private func line(_ p1: CGPoint, _ p2: CGPoint, color: Color) -> some View {
        Path { path in
            path.move(to: p1)
            path.addLine(to: p2)
        }
        .stroke(color, lineWidth: 3)
    }

    private struct OverlayPoints {
        let leftShoulder: CGPoint
        let rightShoulder: CGPoint
        let leftElbow: CGPoint
        let rightElbow: CGPoint
        let leftWrist: CGPoint
        let rightWrist: CGPoint
    }
}
