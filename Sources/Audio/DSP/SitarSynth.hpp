#pragma once
#include <atomic>
#include <cstdint>
#include "DelayLine.hpp"

/// Number of sympathetic (taraf) strings, retuned to the selected scale.
constexpr int kNumSympStrings = 7;

/// Number of parallel combs / series allpasses in the tiny room reverb.
constexpr int kNumReverbCombs     = 2;
constexpr int kNumReverbAllpasses = 2;

/// All UI -> audio-thread communication happens through these atomics.
/// The render thread only ever load()s; the UI thread only ever store()s.
/// No locks, no allocation on the audio thread. Keep it that way.
struct SynthParams {
    std::atomic<float> targetFreqHz { 220.0f };   // continuous pitch target (meend)
    std::atomic<float> velocity     { 0.8f  };    // 0..1, set before pluck
    std::atomic<int>   pluckCount   { 0     };    // increment to trigger a pluck
    // Hammer-on / pull-off: increment to jump to targetFreqHz WITHOUT a full
    // pluck — fast fret-like pitch step (ignores glide) plus a small burst of
    // `legatoAccent` energy, like a finger landing on or leaving the string.
    std::atomic<int>   legatoCount  { 0     };
    std::atomic<float> legatoAccent { 0.0f  };    // 0..1, set before legatoCount
    std::atomic<bool>  gate         { false };    // finger down?
    std::atomic<float> brightness   { 0.6f  };    // XY pad X: string damping
    std::atomic<float> buzz         { 0.4f  };    // XY pad Y: jawari intensity
    // Live per-note dynamics (Apple Pencil pressure). 1 = full / neutral, so
    // finger playing is unaffected. Scales string output and darkens slightly
    // when soft. Never touches loop gain — stability is unchanged.
    std::atomic<float> expression   { 1.0f  };
    std::atomic<float> sympFreqHz[kNumSympStrings]; // sympathetic tunings

    // --- Fader-driven params ------------------------------------------------
    // 0..1 for all four. Sensible mid-defaults so the app sounds good on launch.
    std::atomic<float> sustain      { 0.55f };    // loop-decay "hold" after release
    std::atomic<float> glideAmount  { 0.35f };    // portamento time: 0=fret, 1=vocal
    std::atomic<float> sympMix      { 0.55f };    // dry/wet for the sympathetic halo
    std::atomic<float> roomAmount   { 0.20f };    // tiny plate-ish reverb send

    // --- Sustain button (under the left thumb) ------------------------------
    // While true, the DSP holds gate high regardless of the grid finger state,
    // so the note keeps ringing after the grid finger releases. Falls back to
    // grid-driven gate when released (natural decay via `sustain` fader).
    std::atomic<bool>  sustainHold  { false };

    // --- Vibrato (driven by drag on the sustain button) ---------------------
    // Rate is a plain frequency in Hz. Depth is peak modulation in cents.
    std::atomic<float> vibratoRate  { 5.0f };
    std::atomic<float> vibratoDepth { 0.0f };

    // --- Published from audio thread for UI to read (bloom, meter) ----------
    std::atomic<float> envelopeLevel { 0.0f };    // 0..~1 smoothed |output|

    SynthParams() {
        // Default sympathetic tuning: A minor pentatonic-ish, overwritten by UI.
        const float defaults[kNumSympStrings] = {110.0f, 130.8f, 146.8f, 164.8f, 196.0f, 220.0f, 261.6f};
        for (int i = 0; i < kNumSympStrings; ++i) sympFreqHz[i].store(defaults[i]);
    }
};

/// Monophonic sitar-style voice:
///   - Extended Karplus-Strong plucked string with continuous (fractional) pitch
///   - "Jawari" bridge nonlinearity in the feedback loop for the sitar buzz
///   - Bank of sympathetic string resonators tuned to the selected scale
///   - Tiny Schroeder-style room reverb (2 combs + 2 allpasses)
class SitarSynth {
public:
    void prepare(double sampleRate);

    /// RT-safe. Renders mono float samples.
    void render(float* out, int numFrames);

    SynthParams params;

private:
    inline float whiteNoise() {
        rngState = rngState * 1664525u + 1013904223u;
        return (static_cast<float>(rngState >> 8) / 8388608.0f) - 1.0f; // ~[-1, 1)
    }

    double sr = 48000.0;

    // Main string
    DelayLine mainString;
    float dampState   = 0.0f;   // one-pole damping filter state
    float freqSmooth  = 220.0f; // portamento-smoothed frequency
    float exprSmooth  = 1.0f;   // smoothed `expression` (pressure jitter → zipper noise)

    // Per-sample smoothed copies of block-rate UI params. UI writes arrive as
    // steps once per block (~5 ms); applied raw, a fast XY/fader move or a
    // vibrato release clicks. ~10 ms one-pole on each.
    float paramCoef      = 0.0f;   // set in prepare()
    float brightSmooth   = 0.6f;
    float buzzSmooth     = 0.4f;
    float vibDepthSmooth = 0.0f;
    float sympGainSmooth = 0.0f;
    float roomSmooth     = 0.0f;
    int   lastPluck   = 0;
    int   lastLegato  = 0;
    // Samples left in the post-legato fast-glide window.
    int   legatoFastRemaining = 0;

    // Excitation (short noise burst injected into the loop)
    int   exciteRemaining = 0;
    float exciteAmp       = 0.0f;

    // Sympathetic strings
    DelayLine symp[kNumSympStrings];
    float sympDamp[kNumSympStrings] = {};

    // Room reverb: fixed prime-ish delay lengths, tuned for a small "hall of a room".
    // Buffers are pre-sized in prepare() — no allocation in render().
    DelayLine combs[kNumReverbCombs];
    DelayLine allpasses[kNumReverbAllpasses];
    float combState[kNumReverbCombs]   = {};
    int   combLen[kNumReverbCombs]     = {};
    int   allpassLen[kNumReverbAllpasses] = {};
    float combFeedback = 0.84f;
    float allpassG     = 0.5f;

    // Output smoothing / DC blocker
    float dcX = 0.0f, dcY = 0.0f;

    // Envelope follower, updated per sample, published per block.
    float envFollower = 0.0f;

    // Vibrato LFO phase; wraps mod 2π.
    float lfoPhase = 0.0f;

    uint32_t rngState = 0x1234567u;
};
