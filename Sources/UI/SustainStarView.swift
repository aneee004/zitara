import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

/// Hold-to-sustain button with an eight-point khatam star.
/// While pressed, the DSP holds gate open so the note keeps ringing after the
/// grid finger is lifted. Wobbling the thumb on the button drives vibrato:
///   horizontal Δ → rate (2–8 Hz)
///   distance from anchor → depth (0–30 cents)
struct SustainStarView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeUIView(context: Context) -> SustainStarUIView {
        let v = SustainStarUIView()
        v.onPress = { [weak appState] in
            appState?.setSustainHold(true)
        }
        v.onDrag = { [weak appState] rateHz, depthCents in
            appState?.setVibratoRate(rateHz)
            appState?.setVibratoDepth(depthCents)
        }
        v.onRelease = { [weak appState] in
            appState?.setSustainHold(false)
            appState?.setVibratoDepth(0)
        }
        return v
    }

    func updateUIView(_ uiView: SustainStarUIView, context: Context) {}
}

// MARK: - UIKit implementation
//
// UIKit rather than SwiftUI so the press/drag/release lifecycle is exact and
// low-latency, matching how the grid handles touches. The visuals are pure
// CALayer so we don't fight the touch pipeline for redraws.

final class SustainStarUIView: UIView {

    var onPress:   (() -> Void)?
    var onRelease: (() -> Void)?
    /// Called on every drag update: (rateHz, depthCents).
    var onDrag:    ((Float, Float) -> Void)?

    private let outerRing = CAShapeLayer()
    private let innerDisc = CAShapeLayer()
    private let starLayer = CAShapeLayer()
    private let haloLayer = CAGradientLayer()
    /// Garnet arc around the rim; its length shows vibrato depth so the
    /// otherwise invisible wobble gesture has a visible result.
    private let vibratoArc = CAShapeLayer()

    private var anchor: CGPoint = .zero
    /// Radius (px) at which the drag reaches max depth. Kept in sync with the
    /// button's usable interior in `layoutSubviews`.
    private var dragRadius: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isExclusiveTouch = true

        // Layer order: halo (glow on press) → disc → ring → star → vibrato arc.
        haloLayer.type = .radial
        haloLayer.colors = [
            Theme.brassUI.withAlphaComponent(0.35).cgColor,
            Theme.brassUI.withAlphaComponent(0.08).cgColor,
            Theme.brassUI.withAlphaComponent(0.00).cgColor,
        ]
        haloLayer.locations = [0.0, 0.5, 1.0]
        haloLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        haloLayer.endPoint   = CGPoint(x: 1.0, y: 1.0)
        haloLayer.opacity = 0

        innerDisc.fillColor   = Theme.surfaceRaisedUI.cgColor
        innerDisc.strokeColor = UIColor.clear.cgColor

        outerRing.fillColor   = UIColor.clear.cgColor
        outerRing.strokeColor = Theme.hairlineUI.cgColor
        outerRing.lineWidth   = 1.5

        starLayer.fillColor   = Theme.brassUI.withAlphaComponent(0.10).cgColor
        starLayer.strokeColor = Theme.brassUI.cgColor
        starLayer.lineWidth   = 1.2
        starLayer.lineJoin    = .miter

        vibratoArc.fillColor   = UIColor.clear.cgColor
        vibratoArc.strokeColor = Theme.garnetUI.cgColor
        vibratoArc.lineWidth   = 3
        vibratoArc.lineCap     = .round
        vibratoArc.strokeEnd   = 0

        layer.addSublayer(haloLayer)
        layer.addSublayer(innerDisc)
        layer.addSublayer(outerRing)
        layer.addSublayer(starLayer)
        layer.addSublayer(vibratoArc)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let ringRadius: CGFloat = side / 2 - 2
        let discRadius: CGFloat = ringRadius - 1
        let starRadius: CGFloat = discRadius * 0.42

        // Anchor the drag range to the button's radius.
        dragRadius = ringRadius

        let discPath = UIBezierPath(
            arcCenter: center, radius: discRadius,
            startAngle: 0, endAngle: 2 * .pi, clockwise: true
        ).cgPath
        innerDisc.path = discPath

        let ringPath = UIBezierPath(
            arcCenter: center, radius: ringRadius,
            startAngle: 0, endAngle: 2 * .pi, clockwise: true
        ).cgPath
        outerRing.path = ringPath

        // Arc starts at 12 o'clock and grows clockwise with depth.
        vibratoArc.path = UIBezierPath(
            arcCenter: center, radius: ringRadius,
            startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true
        ).cgPath

        starLayer.path = Self.khatamPath(center: center, radius: starRadius).cgPath

        // Halo spreads past the ring so the glow reads as light, not a fill.
        let haloSide = ringRadius * 3
        haloLayer.frame = CGRect(x: center.x - haloSide / 2,
                                 y: center.y - haloSide / 2,
                                 width: haloSide, height: haloSide)
    }

    // MARK: - Touch pipeline

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        anchor = t.location(in: self)
        onPress?()
        setPressedVisual(true)
        // Reset vibrato at press so an old wobble doesn't linger.
        onDrag?(5.0, 0.0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let dx = p.x - anchor.x
        let dy = p.y - anchor.y
        let dist = min(sqrt(dx * dx + dy * dy), dragRadius)

        // Rate: 2–8 Hz across ±dragRadius horizontally.
        let hNorm = Float(max(-1, min(1, dx / dragRadius)))
        let rateHz = 5.0 + hNorm * 3.0

        // Depth: 0–30 cents by distance from anchor.
        let depthCents = Float(dist / dragRadius) * 30.0

        onDrag?(rateHz, depthCents)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vibratoArc.strokeEnd = dist / dragRadius
        CATransaction.commit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }

    private func release() {
        onRelease?()
        setPressedVisual(false)
    }

    private func setPressedVisual(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        haloLayer.opacity = pressed ? 1.0 : 0.0
        outerRing.strokeColor = (pressed ? Theme.brassUI : Theme.hairlineUI).cgColor
        starLayer.fillColor = Theme.brassUI.withAlphaComponent(pressed ? 0.85 : 0.10).cgColor
        if !pressed { vibratoArc.strokeEnd = 0 }
        CATransaction.commit()
    }

    // MARK: - Star path helper

    /// Eight-point khatam: two squares, one rotated 45°, traced as a single
    /// outline (alternating outer tips and inner notches).
    private static func khatamPath(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        // Inner notch radius where the two squares' edges cross.
        let inner = radius * cos(.pi / 4) / cos(.pi / 8)
        let path = UIBezierPath()
        for i in 0..<16 {
            let r = (i % 2 == 0) ? radius : inner
            let a = -CGFloat.pi / 2 + CGFloat(i) * (.pi / 8)
            let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        return path
    }
}
