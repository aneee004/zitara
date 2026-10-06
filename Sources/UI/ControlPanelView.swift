import SwiftUI

/// The instrument's chrome, grouped by how the hands use it:
///
///   PERFORM  — sustain button + tone pad. Ridden live with the left hand, so
///              they're the largest targets and sit nearest the thumb.
///   PITCH    — live note readout, scale menu, root keyboard. Glanced at
///              during play, touched between pieces.
///   SHAPE    — faders that set the instrument's character. Set-and-forget.
///
/// Portrait lays these out as a top bar; landscape as a left column. Both
/// keep PERFORM nearest the left thumb.
///
/// `isCompact` (anything smaller than the 12.9"/13" iPad on that axis):
/// PERFORM shrinks a little and SHAPE collapses into a button that opens the
/// faders in a popover — they're set-and-forget, so they're what can hide.
struct ControlPanelView: View {
    let isLandscape: Bool
    let isCompact: Bool

    var body: some View {
        Group {
            if isLandscape { column } else { bar }
        }
        .background(Theme.panelBackground)
        .overlay(alignment: isLandscape ? .trailing : .bottom) {
            // Brass trim between chrome and playing surface.
            Rectangle()
                .fill(Theme.brass.opacity(0.22))
                .frame(width: isLandscape ? 1 : nil, height: isLandscape ? nil : 1)
        }
    }

    // MARK: - Portrait: top bar

    private var bar: some View {
        HStack(alignment: .top, spacing: isCompact ? 16 : 20) {
            SustainSection(size: isCompact ? 124 : 140)
            ToneSection(width: isCompact ? 150 : 170, height: 140)
            Hairline(vertical: true).frame(height: 150).padding(.top, 6)
            PitchSection(stacked: false).frame(maxWidth: .infinity)
            Hairline(vertical: true).frame(height: 150).padding(.top, 6)
            if isCompact {
                ShapeButton(vertical: true).frame(width: 56, height: 162)
            } else {
                ShapeSection().frame(height: 162)
            }
        }
        .padding(.horizontal, isCompact ? 16 : 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Landscape: left column

    private var column: some View {
        VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
            SustainSection(size: isCompact ? 112 : 140)
            // The pad absorbs whatever height is left: in a column, more
            // travel on the tone pad is the most useful place for spare room.
            ToneSection(width: 260, height: nil)
            Hairline(vertical: false)
            PitchSection(stacked: true)
            Hairline(vertical: false)
            if isCompact {
                ShapeButton(vertical: false).frame(height: 52)
            } else {
                ShapeSection()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Sections

private struct SustainSection: View {
    @EnvironmentObject var appState: AppState
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Sustain")
                Spacer(minLength: 4)
                vibratoReadout
            }
            SustainButtonView()
                .frame(width: size, height: size)
        }
        .frame(width: size)
    }

    /// Shows what the wobble gesture is doing, only while the button is held.
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

private struct ToneSection: View {
    let width: CGFloat
    /// nil = fill the available height.
    let height: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Tone")
            XYPadView()
                .frame(width: width)
                .frame(height: height)
                .frame(maxHeight: height == nil ? .infinity : nil)
        }
    }
}

private struct PitchSection: View {
    @EnvironmentObject var appState: AppState
    /// Narrow container: put the scale menu under the readout, not beside it.
    let stacked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stacked {
                HStack(alignment: .top) {
                    PitchReadoutView(readout: appState.readout)
                    Spacer(minLength: 8)
                    HelpButton()
                }
                ScaleMenuView(scale: $appState.scale)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    PitchReadoutView(readout: appState.readout)
                    ScaleMenuView(scale: $appState.scale)
                    HelpButton()
                }
            }
            RootKeyboardView(root: $appState.root, coloring: appState.coloring)
        }
    }
}

private struct ShapeSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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
    }
}

/// Compact stand-in for the fader row: four mini level bars (so the
/// settings stay readable at a glance) that open the real faders.
private struct ShapeButton: View {
    @EnvironmentObject var appState: AppState
    let vertical: Bool
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            let layout = vertical
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                levels
                SectionLabel(text: "Shape")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            ShapeSection()
                .frame(width: 240, height: 230)
                .padding(20)
                .background(Theme.panelBackground)
                .environmentObject(appState)
        }
        .accessibilityLabel("Shape faders")
    }

    private var levels: some View {
        HStack(alignment: .bottom, spacing: 4) {
            bar(appState.sustain); bar(appState.glide)
            bar(appState.sympMix); bar(appState.room)
        }
        .frame(height: 28)
    }

    private func bar(_ v: Float) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Theme.hairline)
            Capsule().fill(Theme.brass).frame(height: max(3, 28 * CGFloat(v)))
        }
        .frame(width: 3, height: 28)
    }
}

/// Reopens the first-launch guide.
private struct HelpButton: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button { appState.showingHelp = true } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How to play")
    }
}

private struct Hairline: View {
    let vertical: Bool

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
