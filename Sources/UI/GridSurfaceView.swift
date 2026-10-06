import UIKit

/// The playable grid. UIKit (not SwiftUI) on purpose: raw UITouch handling
/// gives us the lowest-latency, most controllable multitouch pipeline.
///
/// Monophonic, last-note priority:
///  - A new touch always steals the voice.
///  - Sliding a finger horizontally bends pitch continuously (meend).
///  - The row is locked at touch-down; slides are horizontal only (v1).
///
/// Rendering style is "rosewood": flat filled tiles on dark wood — brass for
/// Sa, ivory for in-scale, near-invisible for out-of-scale. While a note
/// sounds, every cell carrying that exact pitch lights up, so the player can
/// see where else on the fourths grid the phrase can continue.
final class GridSurfaceView: UIView {

    // MARK: - Configuration

    var layout: GridLayout = .standard { didSet { setNeedsDisplay() } }
    var coloring: ScaleColoring? { didSet { setNeedsDisplay() } }

    // MARK: - Event callbacks (wired to AudioEngine)

    var onNoteOn: ((Double, Float) -> Void)?
    var onSlide: ((Double) -> Void)?
    var onNoteOff: (() -> Void)?

    /// Returns the live envelope level so the touch overlay can bloom with it.
    var envelopeProvider: (() -> Float)? {
        didSet { feedback.envelopeProvider = envelopeProvider }
    }

    // MARK: - Active touch state (monophonic)

    private var activeTouch: UITouch?
    private var anchorX: CGFloat = 0
    private var anchorMidi: Double = 0
    private var activeRow: Int = 0

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
        isMultipleTouchEnabled = true // we receive all touches; voice stealing picks one
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
        guard let touch = touches.first else { return }
        startNote(with: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        let point = active.location(in: self)
        let deltaSemis = Double((point.x - anchorX) / cellSize)
        onSlide?(anchorMidi + deltaSemis)
        setLit(midi: Int((anchorMidi + deltaSemis).rounded()))
        feedback.moved(to: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endIfActive(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endIfActive(touches)
    }

    private func startNote(with touch: UITouch) {
        let point = touch.location(in: self)
        // Ignore taps in the letterbox — they'd be confusing musically.
        guard pointIsInGrid(point) else { return }

        let r = row(forY: point.y)
        let c = col(forX: point.x)

        activeTouch = touch          // last-note priority: steal unconditionally
        activeRow = r
        // Quantized attack from the cell's screen-center, then slide from there.
        anchorX = gridOrigin.x + (CGFloat(c) + 0.5) * cellSize
        anchorMidi = Double(layout.midiNote(row: r, col: c))

        // Approximate velocity from touch radius (no pressure on iPad touch).
        let radius = touch.majorRadius
        let velocity = Float(min(max((radius - 8) / 30, 0.35), 1.0))

        onNoteOn?(anchorMidi, velocity)
        // Immediately account for finger being off-center at attack:
        let deltaSemis = Double((point.x - anchorX) / cellSize)
        if abs(deltaSemis) > 0.001 { onSlide?(anchorMidi + deltaSemis) }

        setLit(midi: Int(anchorMidi))
        feedback.began(at: point, cellRect: cellRect(row: r, col: c),
                       cornerRadius: Self.cornerRadius)
    }

    private func endIfActive(_ touches: Set<UITouch>) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil
        onNoteOff?()
        setLit(midi: nil)
        feedback.ended()
    }

    // MARK: - Same-pitch lighting

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
        // Geometry changed; recompute the lit path against new cell rects.
        let lit = litMidi
        litMidi = nil
        setLit(midi: lit)
        setNeedsDisplay()
    }
}
