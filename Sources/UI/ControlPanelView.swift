import SwiftUI

/// Top control bar (portrait), grouped by how the hands use it:
///
///   PERFORM  — sustain star + tone pad. Ridden live with the left hand, so
///              they're the largest targets and sit nearest the thumb.
///   PITCH    — live note readout, scale menu, root keyboard. Glanced at
///              during play, touched between pieces.
///   SHAPE    — faders that set the instrument's character. Set-and-forget.
struct ControlBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 20) {

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "Sustain")
                    Spacer(minLength: 4)
                    vibratoReadout
                }
                SustainStarView()
                    .frame(width: 140, height: 140)
            }
            .frame(width: 140)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Tone")
                XYPadView()
                    .frame(width: 170, height: 140)
            }

            divider

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    PitchReadoutView(readout: appState.readout)
                    ScaleMenuView(scale: $appState.scale)
                }
                RootKeyboardView(root: $appState.root, coloring: appState.coloring)
            }
            .frame(maxWidth: .infinity)

            divider

            HStack(spacing: 2) {
                FaderView(label: "Decay",
                          value: Binding(get: { appState.sustain }, set: appState.setSustain),
                          defaultValue: AppState.Defaults.sustain)
                FaderView(label: "Glide",
                          value: Binding(get: { appState.glide }, set: appState.setGlide),
                          defaultValue: AppState.Defaults.glide,
                          // Mirrors glideMs in SitarSynth::render.
                          format: { String(format: "%.0f ms", 0.5 + 49.5 * $0) })
                FaderView(label: "Taraf",
                          value: Binding(get: { appState.sympMix }, set: appState.setSympMix),
                          defaultValue: AppState.Defaults.sympMix)
                FaderView(label: "Room",
                          value: Binding(get: { appState.room }, set: appState.setRoom),
                          defaultValue: AppState.Defaults.room)
            }
            .frame(height: 162)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.panelBackground)
        .overlay(alignment: .bottom) {
            // Brass trim between chrome and playing surface.
            Rectangle()
                .fill(Theme.brass.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 150)
            .padding(.top, 6)
    }

    /// Shows what the wobble gesture is doing, only while the star is held.
    private var vibratoReadout: some View {
        Text(appState.sustainHold && appState.vibratoDepth > 0.5
             ? String(format: "%.1f Hz \u{00B7} %.0f\u{00A2}",
                      appState.vibratoRate, appState.vibratoDepth)
             : " ")
            .font(Theme.serif(10.5).monospacedDigit())
            .foregroundColor(Theme.garnet)
            .lineLimit(1)
            .fixedSize()
    }
}
