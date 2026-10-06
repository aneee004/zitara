#import "SitarSynthBridge.h"
#include "../DSP/SitarSynth.hpp"
#include <algorithm>

@implementation SitarSynthBridge {
    SitarSynth _synth;
}

- (void)prepareWithSampleRate:(double)sampleRate {
    _synth.prepare(sampleRate);
}

- (void)renderInto:(float *)buffer frames:(int)frames {
    _synth.render(buffer, frames);
}

- (void)noteOnWithFrequency:(float)freq velocity:(float)velocity {
    _synth.params.targetFreqHz.store(freq, std::memory_order_relaxed);
    _synth.params.velocity.store(std::clamp(velocity, 0.05f, 1.0f), std::memory_order_relaxed);
    _synth.params.gate.store(true, std::memory_order_relaxed);
    _synth.params.pluckCount.fetch_add(1, std::memory_order_relaxed);
}

- (void)slideToFrequency:(float)freq {
    _synth.params.targetFreqHz.store(freq, std::memory_order_relaxed);
}

- (void)legatoToFrequency:(float)freq accent:(float)accent {
    _synth.params.targetFreqHz.store(freq, std::memory_order_relaxed);
    _synth.params.legatoAccent.store(std::clamp(accent, 0.0f, 1.0f), std::memory_order_relaxed);
    _synth.params.gate.store(true, std::memory_order_relaxed);
    _synth.params.legatoCount.fetch_add(1, std::memory_order_relaxed);
}

- (void)setExpression:(float)value {
    _synth.params.expression.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)noteOff {
    _synth.params.gate.store(false, std::memory_order_relaxed);
}

- (void)setBrightness:(float)value {
    _synth.params.brightness.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setBuzz:(float)value {
    _synth.params.buzz.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setSustain:(float)value {
    _synth.params.sustain.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setGlide:(float)value {
    _synth.params.glideAmount.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setSympMix:(float)value {
    _synth.params.sympMix.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setRoom:(float)value {
    _synth.params.roomAmount.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)setSustainHold:(BOOL)held {
    _synth.params.sustainHold.store(held ? true : false, std::memory_order_relaxed);
}

- (void)setVibratoRate:(float)hz {
    _synth.params.vibratoRate.store(std::clamp(hz, 0.1f, 20.0f), std::memory_order_relaxed);
}

- (void)setVibratoDepth:(float)cents {
    _synth.params.vibratoDepth.store(std::clamp(cents, 0.0f, 100.0f), std::memory_order_relaxed);
}

- (float)envelopeLevel {
    return _synth.params.envelopeLevel.load(std::memory_order_relaxed);
}

- (void)setSympatheticFrequency:(float)freq atIndex:(int)index {
    if (index < 0 || index >= kNumSympStrings) return;
    _synth.params.sympFreqHz[index].store(freq, std::memory_order_relaxed);
}

@end
