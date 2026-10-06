import SwiftUI

/// Bridges the UIKit playing surface into the SwiftUI layout.
struct GridSurfaceRepresentable: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeUIView(context: Context) -> GridSurfaceView {
        let view = GridSurfaceView()
        view.layout = appState.layout
        let readout = appState.readout
        view.onNoteOn = { [weak appState] midi, velocity in
            appState?.audioEngine.noteOn(midi: midi, velocity: velocity)
            readout.noteOn(midi)
        }
        view.onSlide = { [weak appState] midi in
            appState?.audioEngine.slide(midi: midi)
            readout.update(midi)
        }
        view.onNoteOff = { [weak appState] in
            appState?.audioEngine.noteOff()
            readout.noteOff()
        }
        // Touch overlay reads this on its display link.
        view.envelopeProvider = { [weak appState] in
            appState?.audioEngine.envelopeLevel ?? 0
        }
        return view
    }

    func updateUIView(_ uiView: GridSurfaceView, context: Context) {
        // SwiftUI calls this on EVERY AppState change, including XY-pad and
        // fader drags at touch rate. Assign only on real change, otherwise
        // the didSet triggers a full grid redraw per frame of drag.
        if uiView.layout != appState.layout { uiView.layout = appState.layout }
        let coloring = appState.coloring
        if uiView.coloring != coloring { uiView.coloring = coloring }
    }
}
