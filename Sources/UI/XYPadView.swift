import SwiftUI

/// 2D modulation pad. Drag the puck while playing with the other hand.
///   X axis -> brightness (string damping: mellow ... metallic)
///   Y axis -> jawari buzz (clean ... full sitar snarl)
///
/// Bound to AppState so the same params can also be driven elsewhere —
/// moving one updates the other.
struct XYPadView: View {
    @EnvironmentObject var appState: AppState
    @GestureState private var isTouching = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let px = CGFloat(appState.brightness) * size.width
            let py = (1 - CGFloat(appState.buzz)) * size.height

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surfaceRaised)

                // Quarter guides — enough to find a spot again, no more.
                Path { p in
                    for f in [0.25, 0.5, 0.75] as [CGFloat] {
                        p.move(to: CGPoint(x: f * size.width, y: 0))
                        p.addLine(to: CGPoint(x: f * size.width, y: size.height))
                        p.move(to: CGPoint(x: 0, y: f * size.height))
                        p.addLine(to: CGPoint(x: size.width, y: f * size.height))
                    }
                }
                .stroke(Theme.hairline.opacity(0.6), lineWidth: 0.5)

                axisLabels(size: size)

                Path { p in
                    p.move(to: CGPoint(x: px, y: 0))
                    p.addLine(to: CGPoint(x: px, y: size.height))
                    p.move(to: CGPoint(x: 0, y: py))
                    p.addLine(to: CGPoint(x: size.width, y: py))
                }
                .stroke(Theme.brass.opacity(0.25), lineWidth: 1)

                puck
                    .position(x: px, y: py)

                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouching) { _, state, _ in state = true }
                    .onChanged { value in
                        let nx = min(max(value.location.x / size.width, 0), 1)
                        let ny = min(max(1 - value.location.y / size.height, 0), 1)
                        appState.setBrightness(Float(nx))
                        appState.setBuzz(Float(ny))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Tone pad")
        .accessibilityValue("Brightness \(pct(appState.brightness)), buzz \(pct(appState.buzz))")
    }

    private var puck: some View {
        ZStack {
            Circle()
                .stroke(Theme.brass.opacity(isTouching ? 0.45 : 0), lineWidth: 1)
                .frame(width: 44, height: 44)
            Circle()
                .fill(Theme.brass)
                .frame(width: 20, height: 20)
            Circle()
                .fill(Theme.ivory)
                .frame(width: 6, height: 6)
        }
        .animation(.easeOut(duration: 0.12), value: isTouching)
    }

    private func axisLabels(size: CGSize) -> some View {
        let style = Theme.serif(9.5, weight: .semibold)
        return ZStack(alignment: .topLeading) {
            Text("BRIGHT \u{2192}")
                .font(style).tracking(1.2)
                .foregroundColor(Theme.textTertiary)
                .position(x: size.width - 34, y: size.height - 10)
            Text("BUZZ \u{2192}")
                .font(style).tracking(1.2)
                .foregroundColor(Theme.textTertiary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .position(x: 10, y: size.height - 40)
        }
        .allowsHitTesting(false)
    }

    private func pct(_ v: Float) -> String { "\(Int((v * 100).rounded())) percent" }
}
