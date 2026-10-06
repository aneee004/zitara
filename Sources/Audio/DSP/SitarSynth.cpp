#include "SitarSynth.hpp"
#include <cmath>
#include <algorithm>

namespace {
    // Small-signal-gain-compensated "jawari" bridge nonlinearity.
    // Adds the characteristic sitar buzz by asymmetrically shaping the
    // string signal at the bridge reflection. Compensated so the loop's
    // small-signal gain stays <= 1 regardless of buzz amount (stability).
    inline float jawari(float x, float buzz) {
        float shaped = x + buzz * (std::tanh(2.5f * x) - x);
        return shaped / (1.0f + 1.5f * buzz);
    }

    // Schroeder-tuned small-room reverb. These are ratios of Freeverb's
    // classic tunings, scaled to the actual sample rate at prepare() time.
    // Two combs give the "tail", two allpasses smear it. Enough for a subtle
    // room without turning the sitar into a cathedral.
    constexpr float kCombMs[kNumReverbCombs]        = { 29.7f, 37.1f };
    constexpr float kAllpassMs[kNumReverbAllpasses] = {  5.0f, 12.3f };
}

void SitarSynth::prepare(double sampleRate) {
    sr = sampleRate;

    // Max delay supports down to ~15 Hz at 96 kHz; plenty of headroom.
    mainString.resize(8192);
    mainString.clear();
    for (int i = 0; i < kNumSympStrings; ++i) {
        symp[i].resize(8192);
        symp[i].clear();
        sympDamp[i] = 0.0f;
    }

    // Room reverb buffers, sized once here so render() never allocates.
    for (int i = 0; i < kNumReverbCombs; ++i) {
        combLen[i] = std::max(1, static_cast<int>(kCombMs[i] * 0.001f * sr));
        combs[i].resize(combLen[i] + 4);
        combs[i].clear();
        combState[i] = 0.0f;
    }
    for (int i = 0; i < kNumReverbAllpasses; ++i) {
        allpassLen[i] = std::max(1, static_cast<int>(kAllpassMs[i] * 0.001f * sr));
        allpasses[i].resize(allpassLen[i] + 4);
        allpasses[i].clear();
    }

    dampState = 0.0f;
    envFollower = 0.0f;
    freqSmooth = params.targetFreqHz.load(std::memory_order_relaxed);
}

void SitarSynth::render(float* out, int numFrames) {
    // ---- Load parameters once per block (atomics are cheap, but be tidy) ----
    const float targetFreq = params.targetFreqHz.load(std::memory_order_relaxed);
    const float brightness = params.brightness.load(std::memory_order_relaxed);
    const float buzz       = params.buzz.load(std::memory_order_relaxed);
    const bool  gridGate   = params.gate.load(std::memory_order_relaxed);
    const bool  sustHold   = params.sustainHold.load(std::memory_order_relaxed);
    const float sustain    = params.sustain.load(std::memory_order_relaxed);
    const float glideAmt   = params.glideAmount.load(std::memory_order_relaxed);
    const float sympMix    = params.sympMix.load(std::memory_order_relaxed);
    const float roomAmt    = params.roomAmount.load(std::memory_order_relaxed);
    const float vibRate    = params.vibratoRate.load(std::memory_order_relaxed);
    const float vibDepth   = params.vibratoDepth.load(std::memory_order_relaxed);

    // The sustain star holds the note ringing regardless of grid touches.
    const bool  gate = gridGate || sustHold;

    // Pluck trigger: UI increments pluckCount; we detect the change here.
    const int pc = params.pluckCount.load(std::memory_order_relaxed);
    if (pc != lastPluck) {
        lastPluck = pc;
        exciteAmp = 0.5f * params.velocity.load(std::memory_order_relaxed);
        exciteRemaining = static_cast<int>(sr * 0.0025); // 2.5 ms noise burst
    }

    // Damping filter coefficient from brightness (higher = brighter).
    const float dampCoef = 0.10f + 0.85f * brightness;

    // Loop gain: 1.0 while held for a steady tone. On release, `sustain`
    // interpolates between a fast natural decay (~1s) and a very long ring.
    const float releaseGain = 0.9900f + 0.0090f * sustain;   // 0.990 .. 0.999
    const float loopGain    = gate ? 1.0000f : releaseGain;

    // Portamento time constant, live-controlled: ~0.5 ms (fretted) to ~50 ms
    // (vocal). Recomputed per block so a UI change is heard within one buffer.
    const float glideMs = 0.5f + 49.5f * glideAmt;
    const float glideCoef =
        1.0f - std::exp(-1.0f / (glideMs * 0.001f * static_cast<float>(sr)));

    float sympFreq[kNumSympStrings];
    float sympLen[kNumSympStrings];
    for (int k = 0; k < kNumSympStrings; ++k) {
        sympFreq[k] = params.sympFreqHz[k].load(std::memory_order_relaxed);
        if (sympFreq[k] < 20.0f) sympFreq[k] = 20.0f;
        sympLen[k] = static_cast<float>(sr) / sympFreq[k];
    }

    // Sympathetic mix curve: soft, so mid-fader still feels significant.
    // sympGain 0..~0.35; matches the old fixed 0.22 at ~0.5 fader.
    const float sympGain = 0.35f * sympMix;

    // Vibrato: convert cents to a per-sample frequency multiplier via
    //   f' = f * 2^(cents/1200) ≈ f * (1 + cents * ln2 / 1200)
    // We use the exact pow so extreme depths still track correctly.
    const float lfoInc = 2.0f * 3.14159265358979323846f *
                         vibRate / static_cast<float>(sr);

    // ---- Per-sample loop ----
    for (int i = 0; i < numFrames; ++i) {
        // Portamento toward the (continuously updated) target pitch.
        freqSmooth += (targetFreq - freqSmooth) * glideCoef;

        // Vibrato modulation. Skips the pow when depth == 0 — a common case
        // (star button not held) and worth the branch to keep idle CPU low.
        float freqNow = freqSmooth;
        if (vibDepth > 0.0001f) {
            lfoPhase += lfoInc;
            if (lfoPhase > 6.28318530717958647692f) lfoPhase -= 6.28318530717958647692f;
            float cents = vibDepth * std::sin(lfoPhase);
            freqNow = freqSmooth * std::pow(2.0f, cents / 1200.0f);
        }
        float delayLen = static_cast<float>(sr) / freqNow - 1.0f;

        // Main string: read -> damp -> jawari -> feedback write.
        float s = mainString.read(delayLen);
        dampState += dampCoef * (s - dampState);
        float bridged = jawari(dampState, buzz);

        float excite = 0.0f;
        if (exciteRemaining > 0) {
            excite = whiteNoise() * exciteAmp;
            --exciteRemaining;
        }

        mainString.write(excite + bridged * loopGain);
        float mainOut = dampState;

        // Sympathetic strings: lightly driven by the main string, ring freely.
        float sympSum = 0.0f;
        for (int k = 0; k < kNumSympStrings; ++k) {
            float ss = symp[k].read(sympLen[k]);
            sympDamp[k] += 0.30f * (ss - sympDamp[k]);
            symp[k].write(mainOut * 0.018f + sympDamp[k] * 0.9994f);
            sympSum += ss;
        }

        // Dry mix (main + sympathetic halo).
        float dry = mainOut * 0.75f + sympSum * sympGain;

        // Tiny room reverb: parallel combs -> series allpasses.
        // Skipped cleanly when roomAmt == 0 (still writes silence to keep
        // buffers alive so re-enabling doesn't click).
        float wet = 0.0f;
        for (int k = 0; k < kNumReverbCombs; ++k) {
            float delayed = combs[k].read(static_cast<float>(combLen[k]));
            // one-pole damping in the comb keeps it from sounding metallic.
            combState[k] += 0.28f * (delayed - combState[k]);
            combs[k].write(dry + combFeedback * combState[k]);
            wet += delayed;
        }
        wet *= 0.5f;
        for (int k = 0; k < kNumReverbAllpasses; ++k) {
            float delayed = allpasses[k].read(static_cast<float>(allpassLen[k]));
            float vNew = wet + allpassG * delayed;
            allpasses[k].write(vNew);
            wet = -allpassG * vNew + delayed;
        }

        float mixed = dry + roomAmt * wet;

        // DC block, soft-limit.
        dcY = mixed - dcX + 0.995f * dcY;
        dcX = mixed;
        float y = std::tanh(dcY);
        out[i] = y;

        // Envelope follower: fast attack (~5 ms) / slow release (~100 ms).
        // Cheap, monotonic, good enough for a bloom radius.
        float ax = std::fabs(y);
        float coef = (ax > envFollower) ? 0.02f : 0.0004f;
        envFollower += coef * (ax - envFollower);
    }

    // Publish the block-final envelope for the UI overlay to pick up.
    params.envelopeLevel.store(envFollower, std::memory_order_relaxed);
}
