import Foundation
import Combine

/// Single source of truth for the app. Owns the audio engine.
/// Modulation params live here (not just on the AudioEngine) so multiple
/// SwiftUI controls — XY pad + faders — can bind to the same value and
/// stay in sync.
final class AppState: ObservableObject {

    let audioEngine = AudioEngine()
    let readout = PitchReadout()

    /// User-facing message when audio can't run; nil when all is well.
    @Published private(set) var audioError: String?

    /// First-launch help. Persisted so it shows once; reopenable from the UI.
    @Published var showingHelp: Bool

    /// Factory values — initial state and the target of double-tap reset.
    enum Defaults {
        static let brightness: Float = 0.6
        static let buzz:       Float = 0.4
        static let sustain:    Float = 0.55
        static let glide:      Float = 0.35
        static let sympMix:    Float = 0.55
        static let room:       Float = 0.20
    }

    // MARK: - Scale / root

    @Published var scale: Scale = Scale.all[2] {          // Major Pentatonic default
        didSet { retuneSympatheticStrings() }
    }
    @Published var root: RootNote = .d {
        didSet { retuneSympatheticStrings() }
    }

    var coloring: ScaleColoring { ScaleColoring(scale: scale, root: root) }

    // MARK: - Modulation (all 0...1)
    //
    // These are @Published so SwiftUI redraws on change. The setters below
    // are the ONLY writers — they also push to the RT-safe atomics via the
    // AudioEngine. Never mutate the properties directly from a callback that
    // shouldn't drive the engine (there aren't any today, but this keeps the
    // invariant obvious).

    @Published private(set) var brightness: Float = Defaults.brightness
    @Published private(set) var buzz:       Float = Defaults.buzz
    @Published private(set) var sustain:    Float = Defaults.sustain
    @Published private(set) var glide:      Float = Defaults.glide
    @Published private(set) var sympMix:    Float = Defaults.sympMix
    @Published private(set) var room:       Float = Defaults.room

    // Sustain button: held state + vibrato that its drag drives.
    // vibratoDepth in cents (0...50 typical), vibratoRate in Hz (2...8 typical).
    @Published private(set) var sustainHold: Bool  = false
    @Published private(set) var vibratoRate: Float = 5.0
    @Published private(set) var vibratoDepth: Float = 0.0

    func setBrightness(_ v: Float) { brightness = v; audioEngine.setBrightness(v) }
    func setBuzz(_ v: Float)       { buzz       = v; audioEngine.setBuzz(v) }
    func setSustain(_ v: Float)    { sustain    = v; audioEngine.setSustain(v) }
    func setGlide(_ v: Float)      { glide      = v; audioEngine.setGlide(v) }
    func setSympMix(_ v: Float)    { sympMix    = v; audioEngine.setSympMix(v) }
    func setRoom(_ v: Float)       { room       = v; audioEngine.setRoom(v) }

    func setSustainHold(_ held: Bool)     { sustainHold = held;   audioEngine.setSustainHold(held) }
    func setVibratoRate(_ hz: Float)      { vibratoRate = hz;     audioEngine.setVibratoRate(hz) }
    func setVibratoDepth(_ cents: Float)  { vibratoDepth = cents; audioEngine.setVibratoDepth(cents) }

    // MARK: - Init / persistence
    //
    // Saved on backgrounding (see ZitaraApp), not per change: the XY pad and
    // faders change at touch rate and there's no value in writing that often.

    private enum Key {
        static let scale = "scale", root = "root"
        static let brightness = "brightness", buzz = "buzz", sustain = "sustain"
        static let glide = "glide", sympMix = "sympMix", room = "room"
        static let seenHelp = "seenHelp"
    }

    init() {
        let d = UserDefaults.standard
        func float(_ key: String, _ fallback: Float) -> Float {
            d.object(forKey: key) == nil ? fallback : min(max(d.float(forKey: key), 0), 1)
        }
        if let name = d.string(forKey: Key.scale),
           let saved = Scale.all.first(where: { $0.name == name }) {
            scale = saved
        }
        if d.object(forKey: Key.root) != nil,
           let saved = RootNote(rawValue: d.integer(forKey: Key.root)) {
            root = saved
        }
        brightness = float(Key.brightness, Defaults.brightness)
        buzz       = float(Key.buzz,       Defaults.buzz)
        sustain    = float(Key.sustain,    Defaults.sustain)
        glide      = float(Key.glide,      Defaults.glide)
        sympMix    = float(Key.sympMix,    Defaults.sympMix)
        room       = float(Key.room,       Defaults.room)
        showingHelp = !d.bool(forKey: Key.seenHelp)

        audioEngine.onFailure = { [weak self] message in
            self?.audioError = message
        }
    }

    func save() {
        let d = UserDefaults.standard
        d.set(scale.name, forKey: Key.scale)
        d.set(root.rawValue, forKey: Key.root)
        d.set(brightness, forKey: Key.brightness)
        d.set(buzz, forKey: Key.buzz)
        d.set(sustain, forKey: Key.sustain)
        d.set(glide, forKey: Key.glide)
        d.set(sympMix, forKey: Key.sympMix)
        d.set(room, forKey: Key.room)
    }

    func dismissHelp() {
        showingHelp = false
        UserDefaults.standard.set(true, forKey: Key.seenHelp)
    }

    // MARK: - Lifecycle

    /// Back in the foreground: audio may have been stopped while away.
    func resume() {
        audioEngine.resumeIfNeeded()
    }

    func retryAudio() {
        audioEngine.start()
    }

    func start() {
        audioEngine.start()
        retuneSympatheticStrings()
        // Push initial values so the audio thread starts with the same state
        // the UI is showing.
        audioEngine.setBrightness(brightness)
        audioEngine.setBuzz(buzz)
        audioEngine.setSustain(sustain)
        audioEngine.setGlide(glide)
        audioEngine.setSympMix(sympMix)
        audioEngine.setRoom(room)
        audioEngine.setVibratoRate(vibratoRate)
        audioEngine.setVibratoDepth(vibratoDepth)
        audioEngine.setSustainHold(sustainHold)
    }

    /// Tune the 7 sympathetic strings to scale degrees around C3–C5,
    /// so the drone halo always agrees with what's being played.
    private func retuneSympatheticStrings() {
        let rootMidiLow = 48 + root.rawValue // C3-based root
        var notes: [Double] = []
        var degree = 0
        while notes.count < 7 {
            let octave = degree / scale.intervals.count
            let step = scale.intervals[degree % scale.intervals.count]
            notes.append(Double(rootMidiLow + octave * 12 + step))
            degree += 1
        }
        audioEngine.tuneSympatheticStrings(midiNotes: notes)
    }
}
