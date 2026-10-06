import AVFoundation

/// Owns the AVAudioEngine graph and forwards musical events to the C++ synth.
/// All public methods are main-thread; the render block runs on the RT thread
/// and touches nothing but the bridge's render call.
///
/// Survives the things that silently kill audio on iPad: interruptions
/// (calls, Siri, alarms), route/configuration changes (headphones, Bluetooth
/// at a different sample rate) and media-services resets. The synth's
/// parameter atomics live in the bridge, which outlives every rebuild, so the
/// instrument comes back with the same sound.
final class AudioEngine {

    private var engine = AVAudioEngine()
    private let synth = SitarSynthBridge()
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    /// Called on the main thread with a user-facing message when audio can't
    /// start, and with nil once it's running again.
    var onFailure: ((String?) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var configObserver: NSObjectProtocol?

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: session, queue: .main) { [weak self] note in
                self?.handleInterruption(note)
            },
            // The old engine is invalid after a reset; build a fresh one.
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                               object: session, queue: .main) { [weak self] _ in
                self?.rebuild(freshEngine: true)
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            try configureSession()
            try buildAndStart()
            onFailure?(nil)
        } catch {
            isRunning = false
            onFailure?("Zitara couldn\u{2019}t start audio. Another app may be using "
                       + "the audio hardware. (\(error.localizedDescription))")
        }
    }

    /// Re-activates audio if the system stopped it while we were away
    /// (e.g. an interruption that never sent an "ended" notification).
    func resumeIfNeeded() {
        if !engine.isRunning { isRunning = false }
        start()
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback: an instrument should sound even with the silent switch on.
        try session.setCategory(.playback, mode: .default)
        try session.setPreferredIOBufferDuration(0.005) // ~5 ms
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
    }

    private func buildAndStart() throws {
        // Every (re)start goes through here — first launch, foreground,
        // interruption end, retry. Remove any previous node first: two
        // attached nodes would both render the same synth each cycle,
        // advancing it twice and mixing the chunks (audible crackle).
        engine.stop()
        if let old = sourceNode {
            engine.detach(old)
            sourceNode = nil
        }

        // Hardware rate can change between starts (Bluetooth, USB interfaces),
        // so the synth is re-prepared each time. Safe: the engine is stopped,
        // so DelayLine resize happens off the RT thread.
        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        synth.prepare(withSampleRate: sampleRate)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw NSError(domain: "Zitara.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        let bridge = synth
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let ptr = abl[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            bridge.render(into: ptr, frames: Int32(frameCount))
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        sourceNode = node
        observeConfigurationChanges()

        try engine.start()
        isRunning = true
    }

    /// Tear down and start again — after a configuration change or a
    /// media-services reset.
    private func rebuild(freshEngine: Bool) {
        engine.stop()
        if freshEngine {
            // The old engine is dead; its node goes with it.
            engine = AVAudioEngine()
            sourceNode = nil
        }
        isRunning = false
        // Release any sounding note so it doesn't resume mid-air.
        synth.noteOff()
        start()
    }

    private func observeConfigurationChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        // Fires when the output route or hardware format changes; the engine
        // stops itself and must be rewired at the new rate.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak self] _ in
                self?.rebuild(freshEngine: false)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // The system has already paused us. Drop the gate so the note
            // doesn't blare back when we return.
            synth.noteOff()
            synth.setSustainHold(false)
            isRunning = false
        case .ended:
            // Resume regardless of .shouldResume: an instrument should be
            // playable the moment the player comes back to it.
            start()
        @unknown default:
            break
        }
    }

    // MARK: - Note events (monophonic)

    func noteOn(midi: Double, velocity: Float) {
        synth.noteOn(withFrequency: Self.frequency(midi: midi), velocity: velocity)
    }

    func slide(midi: Double) {
        synth.slide(toFrequency: Self.frequency(midi: midi))
    }

    /// Hammer-on / pull-off. Accent is the share of a full pluck's energy:
    /// a hammer-on strikes the string, a pull-off only flicks it.
    func legato(midi: Double, kind: LegatoKind, velocity: Float) {
        let accent: Float = (kind == .hammerOn ? 0.30 : 0.15) * velocity
        synth.legato(toFrequency: Self.frequency(midi: midi), accent: accent)
    }

    func noteOff() {
        synth.noteOff()
    }

    /// Per-note pressure 0...1 (Pencil); 1 for fingers.
    func setPressure(_ value: Float) {
        synth.setExpression(value)
    }

    // MARK: - Modulation (XY pad)

    func setBrightness(_ value: Float) { synth.setBrightness(value) }
    func setBuzz(_ value: Float)       { synth.setBuzz(value) }

    // MARK: - Fader-driven params

    func setSustain(_ value: Float) { synth.setSustain(value) }
    func setGlide(_ value: Float)   { synth.setGlide(value) }
    func setSympMix(_ value: Float) { synth.setSympMix(value) }
    func setRoom(_ value: Float)    { synth.setRoom(value) }

    // MARK: - Sustain button + vibrato

    func setSustainHold(_ held: Bool)    { synth.setSustainHold(held) }
    func setVibratoRate(_ hz: Float)     { synth.setVibratoRate(hz) }
    func setVibratoDepth(_ cents: Float) { synth.setVibratoDepth(cents) }

    /// Cheap read: audio thread stores atomically once per block.
    var envelopeLevel: Float { synth.envelopeLevel() }

    // MARK: - Sympathetic string tuning

    /// Retunes the 7 sympathetic strings to the given MIDI notes.
    func tuneSympatheticStrings(midiNotes: [Double]) {
        for (index, midi) in midiNotes.prefix(7).enumerated() {
            synth.setSympatheticFrequency(Self.frequency(midi: midi), at: Int32(index))
        }
    }

    // MARK: - Helpers

    static func frequency(midi: Double) -> Float {
        Float(440.0 * pow(2.0, (midi - 69.0) / 12.0))
    }
}
