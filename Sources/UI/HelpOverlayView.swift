import SwiftUI

/// First-launch guide (and the "?" button). Nothing on the surface explains
/// meend, the sustain wobble or hammer-ons by itself, so this is the one
/// place that does — short enough to read in the time it takes to tune up.
struct HelpOverlayView: View {
    let onDismiss: () -> Void

    private let items: [(title: String, text: String)] = [
        ("Pluck",           "Tap a cell. Each row is a string; rows rise in fourths."),
        ("Meend",           "Slide sideways to bend pitch smoothly between notes."),
        ("Hammer-on",       "Add a finger on the same row to change note without re-plucking. Lift it to pull off back."),
        ("Sustain & vibrato", "Hold the ring to keep the note ringing. Wobble your thumb on it for vibrato."),
        ("Tone",            "Drag the pad: right is brighter, up is more jawari buzz."),
        ("Apple Pencil",    "Press harder to play louder; ease off to let a note fade."),
        ("Faders",          "Double-tap any fader to reset it."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                Text("Zitara")
                    .font(Theme.serif(30, weight: .medium))
                    .foregroundColor(Theme.brass)
                Text("A sitar you play with your fingertips.")
                    .font(Theme.serif(15))
                    .foregroundColor(Theme.textSecondary)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            SectionLabel(text: item.title)
                            Text(item.text)
                                .font(Theme.serif(15))
                                .foregroundColor(Theme.ivory)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Button(action: onDismiss) {
                    Text("Start playing")
                        .font(Theme.serif(16, weight: .semibold))
                        .foregroundColor(Theme.appBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.brass))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panelBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Shown instead of a silent instrument when audio can't start.
struct AudioErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "speaker.slash")
                .foregroundColor(Theme.garnet)
            Text(message)
                .font(Theme.serif(14))
                .foregroundColor(Theme.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Try again", action: onRetry)
                .font(Theme.serif(14, weight: .semibold))
                .foregroundColor(Theme.brass)
        }
        .padding(16)
        .frame(maxWidth: 620)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.garnet.opacity(0.6), lineWidth: 1))
        .padding(24)
    }
}
