#pragma once
#include <vector>
#include <algorithm>

/// Fractional delay line with linear interpolation.
/// Real-time safety: resize()/clear() must ONLY be called before the audio
/// engine starts (or from a non-RT context while the engine is stopped).
/// write()/read() are RT-safe: no allocation, no locks.
class DelayLine {
public:
    void resize(int maxSamples) {
        buffer.assign(static_cast<size_t>(maxSamples), 0.0f);
        size = maxSamples;
        writeIndex = 0;
    }

    void clear() {
        std::fill(buffer.begin(), buffer.end(), 0.0f);
    }

    inline void write(float x) {
        buffer[static_cast<size_t>(writeIndex)] = x;
        writeIndex += 1;
        if (writeIndex >= size) writeIndex = 0;
    }

    /// Read `delay` samples behind the write head (fractional).
    inline float read(float delay) const {
        // Clamp to a valid range.
        if (delay < 1.0f) delay = 1.0f;
        if (delay > static_cast<float>(size - 2)) delay = static_cast<float>(size - 2);

        float readPos = static_cast<float>(writeIndex) - delay;
        while (readPos < 0.0f) readPos += static_cast<float>(size);

        int i0 = static_cast<int>(readPos);
        int i1 = i0 + 1;
        if (i1 >= size) i1 = 0;
        float frac = readPos - static_cast<float>(i0);

        float a = buffer[static_cast<size_t>(i0)];
        float b = buffer[static_cast<size_t>(i1)];
        return a + frac * (b - a);
    }

private:
    std::vector<float> buffer;
    int size = 1;
    int writeIndex = 0;
};
