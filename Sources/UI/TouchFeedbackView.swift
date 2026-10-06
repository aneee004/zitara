import UIKit

/// Non-interactive overlay that renders touch feedback on top of the grid.
/// Kept quiet on purpose — the lit same-pitch cells carry most of the
/// information; this layer only adds a sense of touch:
///
///   - A single brass ring that eases out from the tapped cell on attack.
///   - A short, thin meend trail (~8 points, 150 ms fade).
///   - A soft radial bloom under the finger whose radius follows the live
///     audio envelope and whose color warms from brass toward ivory as the
///     note gets louder.
///
/// The audio thread publishes the envelope atomically; we sample it on the
/// main thread via a display link. No blocking, no allocation on the RT side.
final class TouchFeedbackView: UIView {

    /// Returns the current smoothed |output|, 0..~1.
    var envelopeProvider: (() -> Float)?

    // MARK: - Layers

    private let bloomLayer  = CAGradientLayer()
    private let trailLayer  = CAShapeLayer()

    // MARK: - Trail state

    private var trailPoints: [CGPoint] = []

    // MARK: - Loop / lifecycle

    private var displayLink: CADisplayLink?
    private var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = false // touches pass through to the grid
        backgroundColor = .clear
        setupBloom()
        setupTrail()
    }

    // MARK: - Public event API (called by GridSurfaceView)

    /// `cellRect` nil = no attack ring (e.g. a pull-off to a finger that was
    /// already down).
    func began(at point: CGPoint, cellRect: CGRect?, cornerRadius: CGFloat) {
        isActive = true
        trailPoints = [point]

        moveBloom(to: point)
        bloomLayer.opacity = 0.5
        trailLayer.opacity = 1.0
        trailLayer.path = nil

        if let cellRect { addAttackRing(rect: cellRect, cornerRadius: cornerRadius) }
        startDisplayLink()
    }

    func moved(to point: CGPoint) {
        trailPoints.append(point)
        // Short tail — shows the meend's direction without cluttering the grid.
        if trailPoints.count > 8 {
            trailPoints.removeFirst(trailPoints.count - 8)
        }

        moveBloom(to: point)
        updateTrailPath()
    }

    func ended() {
        guard isActive else { return }
        isActive = false

        // Quick fade so the trail never lingers behind the next phrase.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        bloomLayer.opacity = 0.0
        trailLayer.opacity = 0.0
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, !self.isActive else { return }
            self.stopDisplayLink()
            self.trailPoints.removeAll()
            self.trailLayer.path = nil
        }
    }

    // MARK: - Setup

    private func setupBloom() {
        // Radial gradient centered in the layer's own bounds — we move the
        // layer's `position` to the touch point and resize `bounds` per
        // envelope tick.
        bloomLayer.type = .radial
        bloomLayer.colors = warmBloomColors()
        bloomLayer.locations = [0.0, 0.35, 1.0]
        bloomLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloomLayer.endPoint   = CGPoint(x: 1.0, y: 1.0)
        bloomLayer.opacity = 0
        // Additive-ish blend so the bloom warms the cells beneath instead of
        // washing them out.
        bloomLayer.compositingFilter = "screenBlendMode"
        layer.addSublayer(bloomLayer)
    }

    private func setupTrail() {
        trailLayer.strokeColor = Theme.brassUI.withAlphaComponent(0.55).cgColor
        trailLayer.fillColor   = UIColor.clear.cgColor
        trailLayer.lineWidth   = 2.5
        trailLayer.lineCap     = .round
        trailLayer.lineJoin    = .round
        trailLayer.opacity     = 0
        trailLayer.compositingFilter = "screenBlendMode"
        layer.addSublayer(trailLayer)
    }

    // MARK: - Bloom / trail updates

    private func moveBloom(to point: CGPoint) {
        // Disable implicit position animation so the bloom snaps to the finger.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloomLayer.position = point
        CATransaction.commit()
    }

    private func updateTrailPath() {
        guard trailPoints.count > 1 else { return }
        let path = UIBezierPath()
        path.move(to: trailPoints[0])
        for p in trailPoints.dropFirst() { path.addLine(to: p) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trailLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func addAttackRing(rect: CGRect, cornerRadius: CGFloat) {
        let duration: CFTimeInterval = 0.28
        let ring = CAShapeLayer()
        ring.frame = rect
        ring.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size),
                                 cornerRadius: cornerRadius).cgPath
        ring.strokeColor = Theme.brassUI.cgColor
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0
        layer.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue   = 1.08

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values   = [0.0, 0.8, 0.0]
        fade.keyTimes = [0.0, 0.12, 1.0]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ring")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            ring.removeFromSuperlayer()
        }
    }

    // MARK: - Display link (envelope)

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        // Weak-target trampoline so the display link doesn't retain us.
        let link = CADisplayLink(target: DisplayLinkProxy(target: self),
                                 selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick() {
        let env = min(max(envelopeProvider?() ?? 0, 0), 1)

        // ---- Bloom radius + color, both env-driven ----
        let base: CGFloat = min(bounds.width, bounds.height) * 0.06
        let radius = base + CGFloat(env) * base * 1.2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloomLayer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        if isActive {
            bloomLayer.opacity = Float(0.25 + 0.35 * CGFloat(env))
            bloomLayer.colors  = bloomColors(hotness: CGFloat(env))
        }
        CATransaction.commit()
    }

    // MARK: - Bloom color helpers

    /// Interpolate gradient between brass (env=0) and warm ivory (env=1).
    /// Same three-stop layout as the initial colors.
    private func bloomColors(hotness t: CGFloat) -> [CGColor] {
        let warm = warmBloomColors()
        let hot  = hotBloomColors()
        return zip(warm, hot).map { a, b in
            lerp(cgColor: a, to: b, t: t)
        }
    }

    private func warmBloomColors() -> [CGColor] {
        [
            Theme.bloomUI.withAlphaComponent(0.70).cgColor,
            Theme.bloomUI.withAlphaComponent(0.25).cgColor,
            Theme.bloomUI.withAlphaComponent(0.00).cgColor,
        ]
    }
    private func hotBloomColors() -> [CGColor] {
        [
            Theme.bloomHotUI.withAlphaComponent(0.80).cgColor,
            Theme.bloomHotUI.withAlphaComponent(0.30).cgColor,
            Theme.bloomHotUI.withAlphaComponent(0.00).cgColor,
        ]
    }

    private func lerp(cgColor a: CGColor, to b: CGColor, t: CGFloat) -> CGColor {
        let ca = a.components ?? [1, 1, 1, 1]
        let cb = b.components ?? [1, 1, 1, 1]
        func mix(_ i: Int) -> CGFloat {
            let av = i < ca.count ? ca[i] : 1
            let bv = i < cb.count ? cb[i] : 1
            return av + (bv - av) * t
        }
        return UIColor(red: mix(0), green: mix(1), blue: mix(2), alpha: mix(3)).cgColor
    }
}

// MARK: - Weak trampoline for CADisplayLink

/// CADisplayLink retains its target. This proxy holds a weak reference so
/// the overlay is deallocated cleanly when the grid goes away.
private final class DisplayLinkProxy: NSObject {
    weak var target: TouchFeedbackView?
    init(target: TouchFeedbackView) { self.target = target }
    @objc func tick() { target?.tick() }
}
