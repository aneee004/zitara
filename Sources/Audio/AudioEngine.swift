import AVFoundation

/// Owns the AVAudioEngine graph and forwards musical events to the C++ synth.
/// All public methods are main-thread; the render block runs on the RT thread
/// and touches nothing but the bridge's render call.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let synth = SitarSynthBridge()
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005) // ~5 ms
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)

            let sampleRate = session.sampleRate
            synth.prepare(withSampleRate: sampleRate)

            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: sampleRate,
                                             channels: 1,
                                             interleaved: false) else { return }

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

            try engine.start()
            isRunning = true
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    // MARK: - Note events (monophonic)

    func noteOn(midi: Double, velocity: Float) {
        synth.noteOn(withFrequency: Self.frequency(midi: midi), velocity: velocity)
    }

    func slide(midi: Double) {
        synth.slide(toFrequency: Self.frequency(midi: midi))
    }

    func noteOff() {
        synth.noteOff()
    }

    // MARK: - Modulation (XY pad)

    func setBrightness(_ value: Float) { synth.setBrightness(value) }
    func setBuzz(_ value: Float)       { synth.setBuzz(value) }

    // MARK: - Fader-driven params

    func setSustain(_ value: Float) { synth.setSustain(value) }
    func setGlide(_ value: Float)   { synth.setGlide(value) }
    func setSympMix(_ value: Float) { synth.setSympMix(value) }
    func setRoom(_ value: Float)    { synth.setRoom(value) }

    // MARK: - Sustain star + vibrato

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
