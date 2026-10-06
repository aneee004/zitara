import Foundation
import Combine

/// Live "what am I playing" state for the note/cents readout.
///
/// Deliberately separate from AppState: it changes at touch rate during a
/// meend, and publishing that from AppState would re-render every control
/// (and the grid representable) on each finger move.
final class PitchReadout: ObservableObject {

    /// Last attacked or slid-to pitch in fractional MIDI. Kept after release
    /// so the readout can dim instead of blanking.
    @Published private(set) var midi: Double?
    @Published private(set) var isSounding = false

    /// Publishing is gated to whole-cent changes; finer motion is invisible.
    private var lastCents = Int.min

    func noteOn(_ midi: Double) {
        isSounding = true
        update(midi)
    }

    func update(_ midi: Double) {
        let cents = Int((midi * 100).rounded())
        guard cents != lastCents else { return }
        lastCents = cents
        self.midi = midi
    }

    func noteOff() {
        isSounding = false
    }
}
