import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

/// Hold-to-sustain button: a thick brass ring with a center dot.
/// While pressed, the DSP holds gate open so the note keeps ringing after the
/// grid finger is lifted. Wobbling the thumb on the button drives vibrato:
///   horizontal Δ → rate (2–8 Hz)
///   distance from anchor → depth (0–30 cents)
struct SustainButtonView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeUIView(context: Context) -> SustainButtonUIView {
        let v = SustainButtonUIView()
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

    func updateUIView(_ uiView: SustainButtonUIView, context: Context) {}
}

// MARK: - UIKit implementation
//
// UIKit rather than SwiftUI so the press/drag/release lifecycle is exact and
// low-latency, matching how the grid handles touches. The visuals are pure
// CALayer so we don't fight the touch pipeline for redraws.

final class SustainButtonUIView: UIView {

    var onPress:   (() -> Void)?
    var onRelease: (() -> Void)?
    /// Called on every drag update: (rateHz, depthCents).
    var onDrag:    ((Float, Float) -> Void)?

    /// Still backdrop — the touch target. Only the ring moves.
    private let baseDisc  = CAShapeLayer()
    /// Ring + fill + dot sway together as one unit during vibrato.
    private let ringGroup = CALayer()
    private let ringFill  = CAShapeLayer()
    private let ring      = CAShapeLayer()
    private let dot       = CAShapeLayer()

    private var anchor: CGPoint = .zero
    private var isPressed = false
    /// Radius (px) at which the drag reaches max depth. Kept in sync with the
    /// button's usable interior in `layoutSubviews`.
    private var dragRadius: CGFloat = 60

    // Vibrato visual: the ring sways at the vibrato rate, wider with depth,
    // so the otherwise invisible wobble gesture has a visible result.
    private var rateHz: Float = 5
    private var depthCents: Float = 0
    private var phase: Double = 0
    private var lastTick: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private let maxSway: CGFloat = 4

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

        baseDisc.fillColor   = Theme.surfaceRaisedUI.cgColor
        baseDisc.strokeColor = Theme.hairlineUI.cgColor
        baseDisc.lineWidth   = 1

        ringFill.fillColor   = Theme.brassUI.cgColor
        ringFill.opacity     = 0

        ring.fillColor       = UIColor.clear.cgColor
        ring.strokeColor     = Self.idleBrass.cgColor

        dot.fillColor        = Self.idleBrass.cgColor

        layer.addSublayer(baseDisc)
        layer.addSublayer(ringGroup)
        ringGroup.addSublayer(ringFill)
        ringGroup.addSublayer(ring)
        ringGroup.addSublayer(dot)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let discRadius = side / 2 - 1
        let ringRadius = discRadius * 0.62
        let ringWidth  = max(5, side * 0.05)

        dragRadius = discRadius
        ringGroup.frame = bounds

        baseDisc.path = Self.circle(center, discRadius)
        ring.path     = Self.circle(center, ringRadius)
        ring.lineWidth = ringWidth
        // Fill covers the ring's full outer edge so pressed reads as one solid disc.
        ringFill.path = Self.circle(center, ringRadius + ringWidth / 2)
        dot.path      = Self.circle(center, max(3, side * 0.03))
    }

    // MARK: - Touch pipeline

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        anchor = t.location(in: self)
        isPressed = true
        onPress?()
        setPressedVisual(true)
        // Reset vibrato at press so an old wobble doesn't linger.
        updateVibrato(rate: 5.0, depth: 0.0)
        startDisplayLink()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let dx = p.x - anchor.x
        let dy = p.y - anchor.y
        let dist = min(sqrt(dx * dx + dy * dy), dragRadius)

        // Rate: 2–8 Hz across ±dragRadius horizontally.
        let hNorm = Float(max(-1, min(1, dx / dragRadius)))
        // Depth: 0–30 cents by distance from anchor.
        updateVibrato(rate: 5.0 + hNorm * 3.0,
                      depth: Float(dist / dragRadius) * 30.0)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release()
    }

    /// Rotation swaps the control layout and tears this view down without a
    /// touchesEnded — release here so sustain can't stay latched on.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, isPressed { release() }
    }

    private func updateVibrato(rate: Float, depth: Float) {
        rateHz = rate
        depthCents = depth
        onDrag?(rate, depth)
    }

    private func release() {
        isPressed = false
        onRelease?()
        setPressedVisual(false)
        stopDisplayLink()
    }

    private func setPressedVisual(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        ringFill.opacity = pressed ? 1 : 0
        ring.strokeColor = (pressed ? Theme.brassUI : Self.idleBrass).cgColor
        dot.fillColor = (pressed ? Theme.appBackgroundUI : Self.idleBrass).cgColor
        if !pressed { ringGroup.transform = CATransform3DIdentity }
        CATransaction.commit()
    }

    // MARK: - Sway loop (main thread, only while pressed)

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        phase = 0
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: SwayProxy(target: self),
                                 selector: #selector(SwayProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick() {
        let now = CACurrentMediaTime()
        // Integrate phase so rate changes mid-wobble don't jump the ring.
        phase += (now - lastTick) * Double(rateHz) * 2 * .pi
        lastTick = now
        let sway = CGFloat(sin(phase)) * maxSway * CGFloat(depthCents / 30)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringGroup.transform = CATransform3DMakeTranslation(sway, 0, 0)
        CATransaction.commit()
    }

    /// Dimmed at rest so the button doesn't outshine the grid; full brass is
    /// reserved for the held state.
    private static let idleBrass = Theme.brassUI.withAlphaComponent(0.6)

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        UIBezierPath(arcCenter: c, radius: r, startAngle: 0,
                     endAngle: 2 * .pi, clockwise: true).cgPath
    }
}

/// CADisplayLink retains its target; this proxy keeps the button deallocatable.
private final class SwayProxy: NSObject {
    weak var target: SustainButtonUIView?
    init(target: SustainButtonUIView) { self.target = target }
    @objc func tick() { target?.tick() }
}
