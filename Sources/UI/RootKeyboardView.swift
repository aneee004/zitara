import SwiftUI

/// Root selector drawn as a one-octave keyboard: naturals on the lower row,
/// sharps offset above. Musicians find a root on a keyboard faster than in a
/// menu, and the keys double as a picture of the scale — in-scale keys are
/// outlined in ivory, the root is solid brass.
struct RootKeyboardView: View {
    @Binding var root: RootNote
    let coloring: ScaleColoring

    private let gap: CGFloat = 4
    private let sharpRowH: CGFloat = 28
    private let naturalRowH: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let naturalW = (geo.size.width - gap * 6) / 7
            let sharpW = naturalW * 0.78

            ZStack(alignment: .topLeading) {
                ForEach(RootNote.allCases) { note in
                    let slot = Self.slot(for: note)
                    let x: CGFloat = note.isNatural
                        ? CGFloat(slot) * (naturalW + gap)
                        // Sharps sit centered on the gap after their natural.
                        : CGFloat(slot + 1) * (naturalW + gap) - gap / 2 - sharpW / 2
                    key(note,
                        width: note.isNatural ? naturalW : sharpW,
                        height: note.isNatural ? naturalRowH : sharpRowH)
                        .offset(x: x, y: note.isNatural ? sharpRowH + gap : 0)
                }
            }
        }
        .frame(height: sharpRowH + gap + naturalRowH)
    }

    private func key(_ note: RootNote, width: CGFloat, height: CGFloat) -> some View {
        let kind = coloring.kind(forPitchClass: note.rawValue)
        let fill: Color = kind == .root ? Theme.brass : Theme.surfaceRaised
        let ink: Color = {
            switch kind {
            case .root:       return Theme.appBackground
            case .inScale:    return Theme.ivory
            case .outOfScale: return Theme.textTertiary
            }
        }()
        let stroke: Color = kind == .inScale ? Theme.ivory.opacity(0.35) : .clear

        return Button { root = note } label: {
            Text(note.displayName)
                .font(Theme.serif(14, weight: kind == .root ? .semibold : .regular))
                .foregroundColor(ink)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Root \(note.displayName)")
        .accessibilityAddTraits(kind == .root ? .isSelected : [])
    }

    /// Index among naturals (for a natural) or of the natural just below (for a sharp).
    private static func slot(for note: RootNote) -> Int {
        let naturalsBelow = RootNote.allCases.prefix(note.rawValue + 1).filter(\.isNatural).count
        return naturalsBelow - 1
    }
}
