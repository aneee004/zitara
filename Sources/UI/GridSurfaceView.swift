import UIKit

/// The playable grid. UIKit (not SwiftUI) on purpose: raw UITouch handling
/// gives us the lowest-latency, most controllable multitouch pipeline.
///
/// Monophonic, last-note priority, played like a string:
///  - A new touch always takes the voice. On a DIFFERENT row (string) it
///    plucks; on the SAME row as the sounding note it's a hammer-on — the
///    pitch steps without a re-pluck, so trills and murki stay legato.
///  - Lifting the sounding finger while others are down pulls off to the
///    most recent finger still down (at wherever it has slid to).
///  - Only the sounding finger bends pitch (meend). The row is locked at
///    touch-down; slides are horizontal only (v1).
///  - Apple Pencil works as a plectrum with pressure: touch-down pressure
///    sets the pluck, and pressure while held swells the note (onPressure).
///    Fingers report a constant full pressure, so they play as before.
///
/// Rendering style is "rosewood": flat filled tiles on dark wood — brass for
/// Sa, ivory for in-scale, near-invisible for out-of-scale. While a note
/// sounds, every cell carrying that exact pitch lights up, so the player can
/// see where else on the fourths grid the phrase can continue.
final class GridSurfaceView: UIView {

    // MARK: - Configuration

    var layout: GridLayout = .portrait {
        didSet {
            guard layout != oldValue else { return }
            // The held cell's row/col no longer means the same pitch; release
            // rather than leave a note stuck on a stale anchor.
            releaseAll()
            setNeedsDisplay()
            refreshLit()
        }
    }
    var coloring: ScaleColoring? { didSet { setNeedsDisplay() } }

    // MARK: - Event callbacks (wired to AudioEngine)

    var onNoteOn: ((Double, Float) -> Void)?
    var onSlide: ((Double) -> Void)?
    /// Pitch change without a pluck: (midi, kind, velocity).
    var onLegato: ((Double, LegatoKind, Float) -> Void)?
    /// Live dynamics of the sounding note, 0...1. Sent before each attack.
    var onPressure: ((Float) -> Void)?
    var onNoteOff: (() -> Void)?

    /// Returns the live envelope level so the touch overlay can bloom with it.
    var envelopeProvider: (() -> Float)? {
        didSet { feedback.envelopeProvider = envelopeProvider }
    }

    // MARK: - Held fingers (monophonic voice, multi-finger stack)

    private struct HeldFinger {
        let touch: UITouch
        let row: Int
        /// Screen x of the attacked cell's center; slides measure from here.
        let anchorX: CGFloat
        let anchorMidi: Double
        var midi: Double
    }

    /// In touch-down order. Invariant: the LAST element is the sounding one.
    private var held: [HeldFinger] = []

    /// Recent pressure of the sounding touch. Pencil force sags as it lifts;
    /// on release we restore the recent peak so the tail isn't choked.
    private var pressureHistory: [(time: TimeInterval, value: Float)] = []
    private static let liftGuardWindow: TimeInterval = 0.08

    // MARK: - Visual overlays

    private let feedback  = TouchFeedbackView()
    /// Brass overlay on all cells matching the sounding pitch. A sublayer
    /// (not part of `draw`) so lighting cells never triggers a full redraw.
    private let litLayer  = CAShapeLayer()
    private var litMidi: Int?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isMultipleTouchEnabled = true // every finger is tracked for hammer-ons / pull-offs
        backgroundColor = Theme.gridCanvasUI
        contentMode = .redraw
        litLayer.fillColor   = Theme.cellLitFillUI.cgColor
        litLayer.strokeColor = Theme.brassUI.cgColor
        litLayer.lineWidth   = 1.5
        layer.addSublayer(litLayer)
        addSubview(feedback)
    }

    // MARK: - Geometry helpers
    //
    // Cells are square: side = min(w/cols, h/rows). The grid is centered
    // inside the view; any leftover space becomes letterbox.

    private var cellSize: CGFloat {
        min(bounds.width  / CGFloat(layout.cols),
            bounds.height / CGFloat(layout.rows))
    }

    private var gridOrigin: CGPoint {
        CGPoint(x: (bounds.width  - cellSize * CGFloat(layout.cols)) / 2,
                y: (bounds.height - cellSize * CGFloat(layout.rows)) / 2)
    }

    private var gridSize: CGSize {
        CGSize(width:  cellSize * CGFloat(layout.cols),
               height: cellSize * CGFloat(layout.rows))
    }

    /// Row 0 is at the BOTTOM of the screen.
    private func row(forY y: CGFloat) -> Int {
        let gy = y - gridOrigin.y
        let r = layout.rows - 1 - Int(gy / cellSize)
        return min(max(r, 0), layout.rows - 1)
    }

    private func col(forX x: CGFloat) -> Int {
        let gx = x - gridOrigin.x
        return min(max(Int(gx / cellSize), 0), layout.cols - 1)
    }

    private func cellRect(row r: Int, col c: Int) -> CGRect {
        let screenRow = layout.rows - 1 - r
        return CGRect(
            x: gridOrigin.x + CGFloat(c) * cellSize,
            y: gridOrigin.y + CGFloat(screenRow) * cellSize,
            width: cellSize,
            height: cellSize
        ).insetBy(dx: 2.5, dy: 2.5)
    }

    private static let cornerRadius: CGFloat = 6

    /// True if `point` is inside the drawn grid (not on a letterbox band).
    private func pointIsInGrid(_ point: CGPoint) -> Bool {
        let gx = point.x - gridOrigin.x
        let gy = point.y - gridOrigin.y
        return gx >= 0 && gy >= 0 &&
               gx < gridSize.width && gy < gridSize.height
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Simultaneous touch-downs are rare; order among them is arbitrary.
        for touch in touches { press(touch) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for i in held.indices where touches.contains(held[i].touch) {
            let point = held[i].touch.location(in: self)
            held[i].midi = held[i].anchorMidi + Double((point.x - held[i].anchorX) / cellSize)
            // Background fingers just track position, ready for a pull-off.
            guard i == held.count - 1 else { continue }
            // Pencil delivers moves on force change alone, so this streams
            // pressure even when the tip is still.
            if held[i].touch.type == .pencil {
                sendPressure(Self.pressure(for: held[i].touch), at: held[i].touch.timestamp)
            }
            onSlide?(held[i].midi)
            setLit(midi: Int(held[i].midi.rounded()))
            feedback.moved(to: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    private func press(_ touch: UITouch) {
        let point = touch.location(in: self)
        // Ignore taps in the letterbox — they'd be confusing musically.
        guard pointIsInGrid(point) else { return }

        let r = row(forY: point.y)
        let c = col(forX: point.x)
        // Quantized attack from the cell's screen-center, then slide from there.
        let anchorX = gridOrigin.x + (CGFloat(c) + 0.5) * cellSize
        let anchorMidi = Double(layout.midiNote(row: r, col: c))
        let midi = anchorMidi + Double((point.x - anchorX) / cellSize)
        let velocity = Self.velocity(for: touch)

        let isHammerOn = held.last?.row == r
        held.append(HeldFinger(touch: touch, row: r, anchorX: anchorX,
                               anchorMidi: anchorMidi, midi: midi))

        // Before the attack, so the pluck starts at the right level.
        pressureHistory.removeAll()
        sendPressure(Self.pressure(for: touch), at: touch.timestamp)

        if isHammerOn {
            onLegato?(midi, .hammerOn, velocity)
        } else {
            onNoteOn?(anchorMidi, velocity)
            // Immediately account for finger being off-center at attack.
            if abs(midi - anchorMidi) > 0.001 { onSlide?(midi) }
        }

        setLit(midi: Int(anchorMidi))
        feedback.began(at: point, cellRect: cellRect(row: r, col: c),
                       cornerRadius: Self.cornerRadius)
    }

    private func lift(_ touches: Set<UITouch>) {
        let wasSounding = held.last.map { touches.contains($0.touch) } ?? false
        held.removeAll { touches.contains($0.touch) }
        guard wasSounding else { return }

        guard let next = held.last else {
            // Restore the recent peak: the tip's sag during lift-off would
            // otherwise mute the release tail.
            if let peak = pressureHistory.map(\.value).max() { onPressure?(peak) }
            pressureHistory.removeAll()
            onNoteOff?()
            setLit(midi: nil)
            feedback.ended()
            return
        }
        // Pull-off: fall back to the most recent finger still down; dynamics
        // now follow that touch.
        pressureHistory.removeAll()
        sendPressure(Self.pressure(for: next.touch), at: next.touch.timestamp)
        onLegato?(next.midi, .pullOff, Self.velocity(for: next.touch))
        setLit(midi: Int(next.midi.rounded()))
        // No ring: that finger was already down; just move the bloom to it.
        feedback.began(at: next.touch.location(in: self), cellRect: nil,
                       cornerRadius: Self.cornerRadius)
    }

    /// Layout swap mid-performance: held fingers' cells no longer mean the
    /// same pitches, so release cleanly rather than leave a stale note.
    private func releaseAll() {
        guard !held.isEmpty else { return }
        held.removeAll()
        pressureHistory.removeAll()
        onNoteOff?()
        setLit(midi: nil)
        feedback.ended()
    }

    private func sendPressure(_ value: Float, at time: TimeInterval) {
        pressureHistory.append((time, value))
        pressureHistory.removeAll { time - $0.time > Self.liftGuardWindow }
        onPressure?(value)
    }

    /// Pencil: pressure-based, with a floor because touch-down force is
    /// usually still ramping (the live swell carries the rest). Finger:
    /// approximated from touch radius, since finger touches report no force.
    private static func velocity(for touch: UITouch) -> Float {
        if touch.type == .pencil {
            return 0.5 + 0.5 * pressure(for: touch)
        }
        return Float(min(max((touch.majorRadius - 8) / 30, 0.35), 1.0))
    }

    /// 0...1 dynamics. Pencil: normalized force, reaching full at half the
    /// device maximum (a firm but comfortable press), on a curve that gives
    /// light touches more resolution. Fingers: always full.
    private static func pressure(for touch: UITouch) -> Float {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return 1 }
        let n = min(touch.force / (touch.maximumPossibleForce * 0.5), 1)
        return Float(pow(n, 0.7))
    }

    // MARK: - Same-pitch lighting

    /// Geometry or layout changed; rebuild the lit path against new cell rects.
    private func refreshLit() {
        let lit = litMidi
        litMidi = nil
        setLit(midi: lit)
    }

    private func setLit(midi: Int?) {
        guard midi != litMidi else { return }
        litMidi = midi
        let path = CGMutablePath()
        if let midi {
            for r in 0..<layout.rows {
                // midi = base + r*rowInterval + c  →  solve for c per row.
                let c = midi - layout.baseMidi - r * layout.rowInterval
                guard (0..<layout.cols).contains(c) else { continue }
                path.addPath(UIBezierPath(roundedRect: cellRect(row: r, col: c),
                                          cornerRadius: Self.cornerRadius).cgPath)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true) // snap — lag here reads as latency
        litLayer.path = path
        CATransaction.commit()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let nameSize = min(cellSize * 0.22, 19)
        let nameFont = Theme.serifUI(nameSize, weight: .medium)
        let octaveFont = Theme.serifUI(nameSize * 0.6, weight: .regular)

        for r in 0..<layout.rows {
            for c in 0..<layout.cols {
                let cell = cellRect(row: r, col: c)
                let pc = layout.pitchClass(row: r, col: c)
                let kind = coloring?.kind(forPitchClass: pc) ?? .outOfScale
                let path = UIBezierPath(roundedRect: cell, cornerRadius: Self.cornerRadius)

                let ink: UIColor
                switch kind {
                case .root:
                    ctx.setFillColor(Theme.cellOutFillUI.cgColor)
                    ctx.addPath(path.cgPath); ctx.fillPath()
                    ctx.setFillColor(Theme.cellRootFillUI.cgColor)
                    ctx.addPath(path.cgPath); ctx.fillPath()
                    ctx.setStrokeColor(Theme.brassUI.withAlphaComponent(0.75).cgColor)
                    ctx.setLineWidth(1.2)
                    ctx.addPath(path.cgPath); ctx.strokePath()
                    drawInlay(in: cell, ctx: ctx)
                    ink = Theme.brassUI

                case .inScale:
                    ctx.setFillColor(Theme.cellOutFillUI.cgColor)
                    ctx.addPath(path.cgPath); ctx.fillPath()
                    ctx.setFillColor(Theme.cellInFillUI.cgColor)
                    ctx.addPath(path.cgPath); ctx.fillPath()
                    ctx.setStrokeColor(Theme.cellInStrokeUI.cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.addPath(path.cgPath); ctx.strokePath()
                    ink = Theme.ivoryUI.withAlphaComponent(0.9)

                case .outOfScale:
                    ctx.setFillColor(Theme.cellOutFillUI.cgColor)
                    ctx.addPath(path.cgPath); ctx.fillPath()
                    ink = Theme.textTertiaryUI
                }

                // Note name; Sa also carries its octave so the player can
                // orient vertically without counting rows.
                let midi = layout.midiNote(row: r, col: c)
                let label = NSMutableAttributedString(
                    string: NoteName.name(forMidi: midi),
                    attributes: [.font: nameFont, .foregroundColor: ink])
                if kind == .root {
                    label.append(NSAttributedString(
                        string: "\(NoteName.octave(forMidi: midi))",
                        attributes: [.font: octaveFont,
                                     .foregroundColor: ink.withAlphaComponent(0.7)]))
                }
                let size = label.size()
                label.draw(at: CGPoint(x: cell.minX + 8,
                                       y: cell.maxY - size.height - 6))
            }
        }
    }

    /// Small brass diamond in the top-right corner of Sa — a nod to fret
    /// inlays, and a second cue besides color for color-blind players.
    private func drawInlay(in cell: CGRect, ctx: CGContext) {
        let s: CGFloat = 4
        let center = CGPoint(x: cell.maxX - 10, y: cell.minY + 10)
        ctx.move(to: CGPoint(x: center.x, y: center.y - s))
        ctx.addLine(to: CGPoint(x: center.x + s, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + s))
        ctx.addLine(to: CGPoint(x: center.x - s, y: center.y))
        ctx.closePath()
        ctx.setFillColor(Theme.brassUI.cgColor)
        ctx.fillPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        feedback.frame = bounds
        litLayer.frame = bounds
        refreshLit()
        setNeedsDisplay()
    }
}
