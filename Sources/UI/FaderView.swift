import SwiftUI

/// Vertical fader styled like a mixing-desk channel: thin track, brass fill,
/// ivory cap. Label above, readout below.
///
/// Drag is RELATIVE — touching the fader never jumps the value, so grabbing
/// it mid-phrase can't cause an audible step. Double-tap restores `defaultValue`.
///
/// Value is in the caller-supplied `range` (defaults to 0...1).
struct FaderView: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var defaultValue: Float? = nil
    /// Formatter for the readout. Defaults to percent of range.
    var format: ((Float) -> String)? = nil

    @State private var dragStartValue: Float?

    private let capH: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            SectionLabel(text: label)

            GeometryReader { geo in
                let h = geo.size.height
                let usableH = h - capH
                let span = range.upperBound - range.lowerBound
                let norm = CGFloat((value - range.lowerBound) / span)
                let capY = (1 - norm) * usableH

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(width: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Capsule()
                        .fill(Theme.brass)
                        .frame(width: 3, height: max(usableH - capY, 0))
                        .frame(maxWidth: .infinity)
                        .offset(y: capY + capH / 2)

                    // Cap with a dark center line, like a physical fader knob.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.ivory)
                        .overlay(Rectangle().fill(Theme.appBackground).frame(height: 1.5))
                        .frame(width: 30, height: capH)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: capY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            let start = dragStartValue ?? value
                            dragStartValue = start
                            let delta = Float(-g.translation.height / max(usableH, 1)) * span
                            value = min(max(start + delta, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in dragStartValue = nil }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if let d = defaultValue { value = d }
                    }
                )
            }
            .frame(width: 50)          // touch target width
            .frame(maxHeight: .infinity)

            Text(readout)
                .font(Theme.serif(12).monospacedDigit())
                .foregroundColor(Theme.ivory)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { dir in
            let step = (range.upperBound - range.lowerBound) * 0.05
            let v = value + (dir == .increment ? step : -step)
            value = min(max(v, range.lowerBound), range.upperBound)
        }
    }

    private var readout: String {
        if let format { return format(value) }
        let n = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return "\(Int((n * 100).rounded()))%"
    }
}
