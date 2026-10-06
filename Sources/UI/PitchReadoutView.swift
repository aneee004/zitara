import SwiftUI

/// Big serif note name + a cents meter. During a meend this is how the
/// player sees how far they've bent and when they've landed on pitch.
/// Dims (rather than blanks) after release so the bar doesn't flicker.
struct PitchReadoutView: View {
    @ObservedObject var readout: PitchReadout

    /// Within this many cents we call it "on pitch" and drop the brass.
    private let inTuneCents = 5

    var body: some View {
        let midi = readout.midi
        let nearest = midi.map { Int($0.rounded()) }
        let cents = midi.map { Int((($0 - $0.rounded()) * 100).rounded()) } ?? 0
        let inTune = abs(cents) <= inTuneCents

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(nearest.map { NoteName.name(forMidi: $0) } ?? "\u{2014}")
                    .font(Theme.serif(32, weight: .medium))
                if let n = nearest {
                    Text("\(NoteName.octave(forMidi: n))")
                        .font(Theme.serif(15))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .foregroundColor(Theme.ivory)

            CentsMeter(cents: cents, inTune: inTune)
                .frame(width: 96, height: 12)

            Text(midi == nil ? " " : String(format: "%+d\u{00A2}", cents))
                .font(Theme.serif(11).monospacedDigit())
                .foregroundColor(inTune ? Theme.textSecondary : Theme.brass)
        }
        .opacity(readout.isSounding ? 1 : 0.45)
        .animation(.easeOut(duration: 0.2), value: readout.isSounding)
        .accessibilityElement()
        .accessibilityLabel("Current note")
        .accessibilityValue(nearest.map { NoteName.name(forMidi: $0) } ?? "None")
    }
}

/// ±50¢ scale with a center tick and a marker.
private struct CentsMeter: View {
    let cents: Int
    let inTune: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x = w / 2 + CGFloat(max(-50, min(50, cents))) / 50 * (w / 2)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: w, height: 1)
                    .offset(y: h / 2)
                Rectangle()
                    .fill(Theme.textTertiary)
                    .frame(width: 1, height: h)
                    .offset(x: w / 2)
                Capsule()
                    .fill(inTune ? Theme.ivory : Theme.brass)
                    .frame(width: 3, height: h)
                    .offset(x: x - 1.5)
            }
        }
    }
}
